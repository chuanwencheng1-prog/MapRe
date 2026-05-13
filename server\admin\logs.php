<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$db = pc_db();
$msg = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['act'] ?? '') === 'clear') {
    pc_check_csrf();
    $days = max(1, (int)($_POST['days'] ?? 30));
    $db->exec("DELETE FROM ".pc_t('logs')." WHERE created_at < ".(time() - $days*86400));
    $msg = '已清理 '.$days.' 天前日志';
    pc_log('log_clear', null, null, ['days'=>$days]);
}

$type = $_GET['type'] ?? '';
$kw   = trim($_GET['kw'] ?? '');
$page = max(1, (int)($_GET['page'] ?? 1));
$size = 50;

$where = []; $args = [];
if ($type) { $where[] = "type=?"; $args[] = $type; }
if ($kw)   { $where[] = "(card LIKE ? OR device_id LIKE ? OR ip LIKE ? OR content LIKE ?)"; $args = array_merge($args, ["%$kw%","%$kw%","%$kw%","%$kw%"]); }
$wsql = $where ? (' WHERE '.implode(' AND ', $where)) : '';

$tot = $db->prepare("SELECT COUNT(*) FROM ".pc_t('logs').$wsql);
$tot->execute($args);
$total = (int)$tot->fetchColumn();

$off = ($page-1)*$size;
$q = $db->prepare("SELECT * FROM ".pc_t('logs').$wsql." ORDER BY id DESC LIMIT $off, $size");
$q->execute($args);
$rows = $q->fetchAll();

$types = $db->query("SELECT DISTINCT type FROM ".pc_t('logs'))->fetchAll(PDO::FETCH_COLUMN);

$_page = 'logs';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">📝 系统日志 <small>(共 <?= $total ?> 条)</small></h1>

<?php if ($msg): ?><div class="alert ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<form class="filter-bar" method="get">
  <input name="kw" placeholder="搜索卡密/设备/IP/内容" value="<?= htmlspecialchars($kw) ?>">
  <select name="type">
    <option value="">全部类型</option>
    <?php foreach ($types as $t): ?>
      <option value="<?= htmlspecialchars($t) ?>" <?= $type===$t?'selected':'' ?>><?= htmlspecialchars($t) ?></option>
    <?php endforeach; ?>
  </select>
  <button class="btn btn-sm">筛选</button>
  <a class="btn btn-sm btn-gray" href="logs.php">重置</a>
  <form method="post" style="display:inline;margin-left:20px">
    <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
    <input type="hidden" name="act" value="clear">
    清理:
    <select name="days"><option value="7">7天前</option><option value="30" selected>30天前</option><option value="90">90天前</option></select>
    <button class="btn btn-sm btn-danger" onclick="return confirm('确认清理日志？')">清理</button>
  </form>
</form>

<div class="panel">
<table class="tbl list">
<thead><tr><th>时间</th><th>类型</th><th>卡密</th><th>设备</th><th>IP</th><th>内容</th></tr></thead>
<tbody>
<?php foreach ($rows as $l): ?>
<tr>
  <td><?= pc_humantime($l['created_at']) ?></td>
  <td><?= htmlspecialchars($l['type']) ?></td>
  <td class="mono"><?= htmlspecialchars($l['card'] ?? '') ?></td>
  <td class="mono"><?= $l['device_id'] ? substr($l['device_id'],0,12).'…' : '' ?></td>
  <td><?= htmlspecialchars($l['ip']) ?></td>
  <td class="dim"><?= htmlspecialchars(mb_substr((string)$l['content'], 0, 200)) ?></td>
</tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="6" class="empty">暂无日志</td></tr><?php endif; ?>
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
<?php include __DIR__ . '/../includes/footer.php'; ?>
