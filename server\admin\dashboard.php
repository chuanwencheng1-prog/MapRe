<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$db = pc_db();
$now = time();

// 自动把到期未置 3 的卡更新为已过期
$db->exec("UPDATE ".pc_t('cards')." SET status=3 WHERE status=1 AND expires_at IS NOT NULL AND expires_at <= {$now}");

$total  = (int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards'))->fetchColumn();
$active = (int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards')." WHERE status=1")->fetchColumn();
$unused = (int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards')." WHERE status=0")->fetchColumn();
$expired= (int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards')." WHERE status=3")->fetchColumn();
$disabled=(int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards')." WHERE status=2")->fetchColumn();
$devTotal=(int)$db->query("SELECT COUNT(*) FROM ".pc_t('devices'))->fetchColumn();
$devActive=(int)$db->query("SELECT COUNT(*) FROM ".pc_t('devices')." WHERE last_seen > ".($now-86400))->fetchColumn();

// 最近 7 天激活数
$days7 = [];
for ($i = 6; $i >= 0; $i--) {
    $d0 = strtotime(date('Y-m-d', $now - $i*86400));
    $d1 = $d0 + 86400;
    $n = (int)$db->query("SELECT COUNT(*) FROM ".pc_t('cards')." WHERE bound_at>={$d0} AND bound_at<{$d1}")->fetchColumn();
    $days7[] = ['date'=>date('m-d', $d0), 'n'=>$n];
}

// 即将到期（24h 内）
$soonRows = $db->query("SELECT card_key,type,expires_at,device_id FROM ".pc_t('cards')." WHERE status=1 AND expires_at BETWEEN {$now} AND ".($now+86400)." ORDER BY expires_at ASC LIMIT 10")->fetchAll();
// 最近活动
$logs = $db->query("SELECT * FROM ".pc_t('logs')." ORDER BY id DESC LIMIT 10")->fetchAll();

$_page = 'dash';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">📊 仪表盘</h1>

<div class="cards-grid">
  <div class="stat-card c1">
    <div class="stat-label">卡密总数</div>
    <div class="stat-num"><?= $total ?></div>
    <div class="stat-sub">累计生成</div>
  </div>
  <div class="stat-card c2">
    <div class="stat-label">已激活</div>
    <div class="stat-num"><?= $active ?></div>
    <div class="stat-sub"><?= $total?round($active/$total*100,1):0 ?>% 激活率</div>
  </div>
  <div class="stat-card c3">
    <div class="stat-label">未激活</div>
    <div class="stat-num"><?= $unused ?></div>
    <div class="stat-sub">库存中</div>
  </div>
  <div class="stat-card c4">
    <div class="stat-label">已过期</div>
    <div class="stat-num"><?= $expired ?></div>
    <div class="stat-sub">已下线</div>
  </div>
  <div class="stat-card c5">
    <div class="stat-label">已禁用</div>
    <div class="stat-num"><?= $disabled ?></div>
    <div class="stat-sub">人工封停</div>
  </div>
  <div class="stat-card c6">
    <div class="stat-label">设备总数</div>
    <div class="stat-num"><?= $devTotal ?></div>
    <div class="stat-sub">24h 活跃 <?= $devActive ?></div>
  </div>
</div>

<div class="two-col">
  <div class="panel">
    <div class="panel-hd">📈 最近 7 天激活趋势</div>
    <div class="panel-bd">
      <div class="bars">
        <?php $max = max(1, max(array_column($days7,'n'))); foreach ($days7 as $d): ?>
          <div class="bar" title="<?= $d['date'] ?>: <?= $d['n'] ?>">
            <div class="bar-fill" style="height: <?= round($d['n']/$max*100) ?>%"></div>
            <div class="bar-num"><?= $d['n'] ?></div>
            <div class="bar-label"><?= $d['date'] ?></div>
          </div>
        <?php endforeach; ?>
      </div>
    </div>
  </div>
  <div class="panel">
    <div class="panel-hd">⏰ 即将到期（24 小时内）</div>
    <div class="panel-bd">
      <?php if (!$soonRows): ?>
        <div class="empty">暂无即将到期卡密</div>
      <?php else: ?>
        <table class="tbl">
          <thead><tr><th>卡密</th><th>类型</th><th>到期时间</th><th>剩余</th></tr></thead>
          <tbody>
          <?php foreach ($soonRows as $r): ?>
            <tr>
              <td class="mono copy" data-copy="<?= htmlspecialchars($r['card_key']) ?>"><?= htmlspecialchars($r['card_key']) ?></td>
              <td><?= pc_type_label($r['type']) ?></td>
              <td><?= pc_humantime($r['expires_at']) ?></td>
              <td><?= pc_left_human($r['expires_at']) ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      <?php endif; ?>
    </div>
  </div>
</div>

<div class="panel">
  <div class="panel-hd">📝 最近活动</div>
  <div class="panel-bd">
    <?php if (!$logs): ?><div class="empty">暂无活动</div><?php else: ?>
    <table class="tbl">
      <thead><tr><th>时间</th><th>类型</th><th>卡密</th><th>设备</th><th>IP</th><th>备注</th></tr></thead>
      <tbody>
      <?php foreach ($logs as $l): ?>
        <tr>
          <td><?= pc_humantime($l['created_at']) ?></td>
          <td><?= htmlspecialchars($l['type']) ?></td>
          <td class="mono"><?= htmlspecialchars($l['card'] ?? '') ?></td>
          <td class="mono"><?= $l['device_id'] ? substr($l['device_id'],0,10).'…' : '' ?></td>
          <td><?= htmlspecialchars($l['ip']) ?></td>
          <td class="dim"><?= htmlspecialchars(mb_substr((string)$l['content'],0,60)) ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
    <?php endif; ?>
  </div>
</div>

<?php include __DIR__ . '/../includes/footer.php'; ?>
