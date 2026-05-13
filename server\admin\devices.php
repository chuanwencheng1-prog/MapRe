<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$db = pc_db();
$msg = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    pc_check_csrf();
    $act = $_POST['act'] ?? '';
    $ids = array_filter(array_map('intval', (array)($_POST['ids'] ?? [])));
    if (!$ids) { $msg = '未选择设备'; }
    else {
        $in = implode(',', $ids);
        if ($act === 'kick') {
            // 踢下线：把设备关联卡置为禁用 + 设备置为封禁
            $db->exec("UPDATE ".pc_t('devices')." SET status=0 WHERE id IN ($in)");
            $db->exec("UPDATE ".pc_t('cards')." c JOIN ".pc_t('devices')." d ON d.card_id=c.id SET c.status=2 WHERE d.id IN ($in)");
            $msg = '已踢下线 '.count($ids).' 台设备并禁用其卡';
            pc_log('dev_kick', null, null, ['ids'=>$ids]);
        } elseif ($act === 'reset') {
            // 重置：解除卡密绑定，设备记录保留
            $db->exec("UPDATE ".pc_t('cards')." c JOIN ".pc_t('devices')." d ON d.card_id=c.id SET c.device_id=NULL,c.bound_at=NULL,c.expires_at=NULL,c.status=0 WHERE d.id IN ($in)");
            $db->exec("UPDATE ".pc_t('devices')." SET card_id=NULL WHERE id IN ($in)");
            $msg = '已解除 '.count($ids).' 台设备与卡密的绑定';
            pc_log('dev_reset', null, null, ['ids'=>$ids]);
        } elseif ($act === 'delete') {
            $db->exec("DELETE FROM ".pc_t('devices')." WHERE id IN ($in)");
            $msg = '已删除 '.count($ids).' 条设备记录';
            pc_log('dev_delete', null, null, ['ids'=>$ids]);
        }
    }
}

$kw   = trim($_GET['kw'] ?? '');
$page = max(1, (int)($_GET['page'] ?? 1));
$size = 30;
$where = []; $args = [];
if ($kw !== '') { $where[] = "(d.device_id LIKE ? OR d.name LIKE ? OR d.ip LIKE ? OR d.bundle LIKE ?)"; $args = ["%$kw%","%$kw%","%$kw%","%$kw%"]; }
$wsql = $where ? (' WHERE '.implode(' AND ', $where)) : '';

$tot = $db->prepare("SELECT COUNT(*) FROM ".pc_t('devices')." d $wsql");
$tot->execute($args);
$total = (int)$tot->fetchColumn();

$off = ($page-1)*$size;
$q = $db->prepare("SELECT d.*, c.card_key, c.type AS card_type, c.expires_at
                   FROM ".pc_t('devices')." d
                   LEFT JOIN ".pc_t('cards')." c ON c.id=d.card_id
                   $wsql ORDER BY d.last_seen DESC LIMIT $off, $size");
$q->execute($args);
$rows = $q->fetchAll();

$now = time();
$_page = 'dev';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">📱 设备管理 <small>(共 <?= $total ?> 台)</small></h1>

<?php if ($msg): ?><div class="alert ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<form class="filter-bar" method="get">
  <input name="kw" placeholder="搜索机器码/设备名/IP/Bundle" value="<?= htmlspecialchars($kw) ?>" style="min-width:260px">
  <button class="btn btn-sm">筛选</button>
  <a class="btn btn-sm btn-gray" href="devices.php">重置</a>
</form>

<form method="post" id="bulkForm">
<input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
<div class="bulk-bar">
  批量操作：
  <button type="button" class="btn btn-sm btn-danger" data-bulk="kick">🚫 踢下线并禁卡</button>
  <button type="button" class="btn btn-sm" data-bulk="reset">🔄 解除绑定</button>
  <button type="button" class="btn btn-sm" data-bulk="delete">🗑️ 删除记录</button>
  <span class="dim" id="selCount" style="margin-left:12px">已选 0 台</span>
</div>

<div class="panel">
<table class="tbl list">
<thead><tr>
  <th style="width:28px"><input type="checkbox" id="selAll"></th>
  <th>ID</th>
  <th>机器码（点击复制）</th>
  <th>设备名</th>
  <th>型号</th>
  <th>系统</th>
  <th>Bundle</th>
  <th>绑定卡密</th>
  <th>到期</th>
  <th>IP</th>
  <th>最近活跃</th>
  <th>状态</th>
</tr></thead>
<tbody>
<?php foreach ($rows as $r):
  $online = $r['last_seen'] >= ($now - 1800); // 30min
?>
  <tr>
    <td><input type="checkbox" name="ids[]" value="<?= (int)$r['id'] ?>" class="rowChk"></td>
    <td><?= (int)$r['id'] ?></td>
    <td class="mono copy" data-copy="<?= htmlspecialchars($r['device_id']) ?>" title="点击复制"><?= substr($r['device_id'],0,16) ?>…</td>
    <td><?= htmlspecialchars($r['name'] ?? '') ?></td>
    <td class="mono"><?= htmlspecialchars($r['model'] ?? '') ?></td>
    <td><?= htmlspecialchars($r['sys'] ?? '') ?></td>
    <td class="mono dim"><?= htmlspecialchars($r['bundle'] ?? '') ?></td>
    <td class="mono copy" data-copy="<?= htmlspecialchars($r['card_key'] ?? '') ?>"><?= htmlspecialchars($r['card_key'] ?? '-') ?></td>
    <td><?= pc_humantime($r['expires_at']) ?></td>
    <td><?= htmlspecialchars($r['ip'] ?? '') ?></td>
    <td><?= pc_humantime($r['last_seen']) ?></td>
    <td><?= $r['status']==0 ? '<span class="pill pill-red">已封禁</span>' : ($online ? '<span class="pill pill-green">在线</span>' : '<span class="pill pill-gray">离线</span>') ?></td>
  </tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="12" class="empty">暂无设备</td></tr><?php endif; ?>
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
</div>
<?php endif; ?>

<input type="hidden" name="act" id="actInput">
</form>

<script>
document.getElementById('selAll').onchange = function(){
  document.querySelectorAll('.rowChk').forEach(c => c.checked = this.checked);
  updateSel();
};
document.querySelectorAll('.rowChk').forEach(c => c.onchange = updateSel);
function updateSel(){
  document.getElementById('selCount').textContent = '已选 '+document.querySelectorAll('.rowChk:checked').length+' 台';
}
document.querySelectorAll('[data-bulk]').forEach(b=>{
  b.onclick = function(){
    var n = document.querySelectorAll('.rowChk:checked').length;
    if (!n) return alert('请先勾选设备');
    var act = b.dataset.bulk;
    var tips = {kick:'确认踢下线 '+n+' 台设备并禁用其卡密？', delete:'确认删除 '+n+' 条设备记录？'};
    if (tips[act] && !confirm(tips[act])) return;
    document.getElementById('actInput').value = act;
    document.getElementById('bulkForm').submit();
  };
});
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
