<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$db = pc_db();
$msg = '';

// 动作处理
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    pc_check_csrf();
    $act = $_POST['act'] ?? '';
    $ids = array_filter(array_map('intval', (array)($_POST['ids'] ?? [])));
    $now = time();

    if ($act === 'disable' && $ids) {
        $in = implode(',', array_map('intval', $ids));
        $db->exec("UPDATE ".pc_t('cards')." SET status=2 WHERE id IN ($in)");
        $msg = '已禁用 '.count($ids).' 张';
        pc_log('card_disable', null, null, ['ids'=>$ids]);
    } elseif ($act === 'enable' && $ids) {
        $in = implode(',', array_map('intval', $ids));
        $db->exec("UPDATE ".pc_t('cards')." SET status=IF(expires_at IS NULL OR expires_at=0, 0, IF(expires_at<=$now, 3, 1)) WHERE id IN ($in)");
        $msg = '已恢复 '.count($ids).' 张';
        pc_log('card_enable', null, null, ['ids'=>$ids]);
    } elseif ($act === 'unbind' && $ids) {
        $in = implode(',', array_map('intval', $ids));
        $db->exec("UPDATE ".pc_t('cards')." SET device_id=NULL,bound_at=NULL,expires_at=NULL,status=0 WHERE id IN ($in)");
        $msg = '已解绑 '.count($ids).' 张（状态重置为未激活）';
        pc_log('card_unbind', null, null, ['ids'=>$ids]);
    } elseif ($act === 'delete' && $ids) {
        $in = implode(',', array_map('intval', $ids));
        $db->exec("DELETE FROM ".pc_t('cards')." WHERE id IN ($in)");
        $msg = '已删除 '.count($ids).' 张';
        pc_log('card_delete', null, null, ['ids'=>$ids]);
    } elseif ($act === 'extend' && $ids) {
        $sec = (int)($_POST['extend_sec'] ?? 0);
        if ($sec > 0) {
            $in = implode(',', array_map('intval', $ids));
            // 对已激活的卡延长；未激活的只改 duration
            $db->exec("UPDATE ".pc_t('cards')." SET expires_at = IF(expires_at IS NULL, NULL, expires_at + $sec), duration = duration + $sec, status=IF(status=3 AND expires_at + $sec > $now, 1, status) WHERE id IN ($in)");
            $msg = '已为 '.count($ids).' 张卡增加 '.floor($sec/3600).' 小时';
            pc_log('card_extend', null, null, ['ids'=>$ids, 'sec'=>$sec]);
        }
    }
}

// 搜索/筛选
$kw     = trim($_GET['kw'] ?? '');
$status = $_GET['status'] ?? '';
$type   = $_GET['type'] ?? '';
$batch  = trim($_GET['batch'] ?? '');
$page   = max(1, (int)($_GET['page'] ?? 1));
$size   = 30;

$where = []; $args = [];
if ($kw !== '')     { $where[] = "(card_key LIKE ? OR device_id LIKE ? OR note LIKE ?)"; $args[] = "%$kw%"; $args[] = "%$kw%"; $args[] = "%$kw%"; }
if ($status !== '') { $where[] = "status=?"; $args[] = (int)$status; }
if ($type !== '')   { $where[] = "type=?";   $args[] = $type; }
if ($batch !== '')  { $where[] = "batch=?";  $args[] = $batch; }
$wsql = $where ? (' WHERE '.implode(' AND ', $where)) : '';

$tot = $db->prepare("SELECT COUNT(*) FROM ".pc_t('cards').$wsql);
$tot->execute($args);
$total = (int)$tot->fetchColumn();

$off = ($page-1)*$size;
$q = $db->prepare("SELECT * FROM ".pc_t('cards').$wsql." ORDER BY id DESC LIMIT $off, $size");
$q->execute($args);
$rows = $q->fetchAll();

$_page = 'cards';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">🎫 卡密管理 <small>(共 <?= $total ?> 张)</small></h1>

<?php if ($msg): ?><div class="alert ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<form class="filter-bar" method="get">
  <input name="kw"    placeholder="搜索卡密/设备/备注" value="<?= htmlspecialchars($kw) ?>">
  <select name="status">
    <option value="">全部状态</option>
    <option value="0" <?= $status==='0'?'selected':'' ?>>未激活</option>
    <option value="1" <?= $status==='1'?'selected':'' ?>>已激活</option>
    <option value="2" <?= $status==='2'?'selected':'' ?>>已禁用</option>
    <option value="3" <?= $status==='3'?'selected':'' ?>>已过期</option>
  </select>
  <select name="type">
    <option value="">全部类型</option>
    <?php foreach (['hour','day','week','month','year','perm'] as $t): ?>
      <option value="<?= $t ?>" <?= $type===$t?'selected':'' ?>><?= pc_type_label($t) ?></option>
    <?php endforeach; ?>
  </select>
  <input name="batch" placeholder="批次号" value="<?= htmlspecialchars($batch) ?>">
  <button class="btn btn-sm">筛选</button>
  <a class="btn btn-sm btn-gray" href="cards.php">重置</a>
  <a class="btn btn-sm btn-primary" href="generate.php">➕ 新建</a>
</form>

<form method="post" id="bulkForm">
<input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
<div class="bulk-bar">
  批量操作：
  <button type="button" class="btn btn-sm" data-bulk="disable">禁用</button>
  <button type="button" class="btn btn-sm" data-bulk="enable">恢复</button>
  <button type="button" class="btn btn-sm" data-bulk="unbind">解绑设备</button>
  <button type="button" class="btn btn-sm" data-bulk="extend">延长</button>
  <button type="button" class="btn btn-sm btn-danger" data-bulk="delete">删除</button>
  <span class="dim" id="selCount" style="margin-left:12px">已选 0 张</span>
</div>

<div class="panel">
<table class="tbl list">
<thead>
  <tr>
    <th style="width:28px"><input type="checkbox" id="selAll"></th>
    <th>ID</th>
    <th>卡密（点击复制）</th>
    <th>类型</th>
    <th>状态</th>
    <th>设备</th>
    <th>激活时间</th>
    <th>到期时间</th>
    <th>剩余</th>
    <th>备注</th>
  </tr>
</thead>
<tbody>
<?php foreach ($rows as $r): ?>
  <tr>
    <td><input type="checkbox" name="ids[]" value="<?= (int)$r['id'] ?>" class="rowChk"></td>
    <td><?= (int)$r['id'] ?></td>
    <td class="mono copy" data-copy="<?= htmlspecialchars($r['card_key']) ?>" title="点击复制"><?= htmlspecialchars($r['card_key']) ?></td>
    <td><?= pc_type_label($r['type']) ?></td>
    <td><?= pc_status_label($r['status']) ?></td>
    <td class="mono"><?= $r['device_id'] ? '<span title="'.htmlspecialchars($r['device_id']).'">'.substr($r['device_id'],0,12).'…</span>' : '<span class="dim">未绑定</span>' ?></td>
    <td><?= pc_humantime($r['bound_at']) ?></td>
    <td><?= pc_humantime($r['expires_at']) ?></td>
    <td><?= pc_left_human($r['expires_at']) ?></td>
    <td class="dim"><?= htmlspecialchars($r['note'] ?? '') ?></td>
  </tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="10" class="empty">暂无数据</td></tr><?php endif; ?>
</tbody>
</table>
</div>

<?php
$pages = max(1, ceil($total/$size));
if ($pages > 1):
?>
<div class="pager">
  <?php for ($i=max(1,$page-3); $i<=min($pages,$page+3); $i++): ?>
    <a class="<?= $i==$page?'active':'' ?>" href="?<?= http_build_query(array_merge($_GET,['page'=>$i])) ?>"><?= $i ?></a>
  <?php endfor; ?>
  <span class="dim">共 <?= $pages ?> 页</span>
</div>
<?php endif; ?>

<input type="hidden" name="act" id="actInput">
<input type="hidden" name="extend_sec" id="extendSec">
</form>

<script>
document.getElementById('selAll').onchange = function(){
  document.querySelectorAll('.rowChk').forEach(c => c.checked = this.checked);
  updateSel();
};
document.querySelectorAll('.rowChk').forEach(c => c.onchange = updateSel);
function updateSel(){
  var n = document.querySelectorAll('.rowChk:checked').length;
  document.getElementById('selCount').textContent = '已选 '+n+' 张';
}
document.querySelectorAll('[data-bulk]').forEach(b=>{
  b.onclick = function(){
    var n = document.querySelectorAll('.rowChk:checked').length;
    if (!n) return alert('请先勾选卡密');
    var act = b.dataset.bulk;
    if (act === 'delete' && !confirm('确认删除选中 '+n+' 张卡密？此操作不可恢复。')) return;
    if (act === 'extend') {
      var h = prompt('延长多少小时？', '24');
      if (!h || isNaN(h) || h<=0) return;
      document.getElementById('extendSec').value = Math.round(h*3600);
    }
    document.getElementById('actInput').value = act;
    document.getElementById('bulkForm').submit();
  };
});
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
