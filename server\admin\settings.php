<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
require_once __DIR__ . '/../includes/rsa.php';
pc_require_login();

$cfg = pc_cfg();
$msg = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    pc_check_csrf();
    $act = $_POST['act'] ?? '';
    if ($act === 'change_pwd') {
        $cur = (string)($_POST['cur'] ?? '');
        $new = (string)($_POST['new'] ?? '');
        if (strlen($new) < 6) { $msg = '新密码至少 6 位'; }
        else {
            $u = pc_admin_user();
            $r = pc_db()->prepare("SELECT password FROM ".pc_t('admin')." WHERE id=?");
            $r->execute([$u['id']]);
            $row = $r->fetch();
            if (!$row || !password_verify($cur, $row['password'])) {
                $msg = '当前密码错误';
            } else {
                pc_db()->prepare("UPDATE ".pc_t('admin')." SET password=? WHERE id=?")
                       ->execute([password_hash($new, PASSWORD_DEFAULT), $u['id']]);
                $msg = '密码已更新';
                pc_log('pwd_change', null, null, ['user'=>$u['username']]);
            }
        }
    }
}

$pub = pc_rsa_public_pem();
$_page = 'set';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">⚙️ 系统设置</h1>

<?php if ($msg): ?><div class="alert ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<div class="two-col">
  <div class="panel">
    <div class="panel-hd">站点信息</div>
    <div class="panel-bd">
      <table class="tbl kv">
        <tr><th>站点名称</th><td><?= htmlspecialchars($cfg['site_name']) ?></td></tr>
        <tr><th>APP_ID</th><td class="mono"><?= htmlspecialchars($cfg['app_id']) ?></td></tr>
        <tr><th>数据库</th><td><?= htmlspecialchars($cfg['db']['host']) ?>:<?= (int)$cfg['db']['port'] ?> / <?= htmlspecialchars($cfg['db']['name']) ?></td></tr>
        <tr><th>API URL</th><td class="mono"><?= (isset($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off'?'https://':'http://').$_SERVER['HTTP_HOST'].dirname(dirname($_SERVER['PHP_SELF'])).'/api.php' ?></td></tr>
        <tr><th>当前时间</th><td><?= date('Y-m-d H:i:s') ?></td></tr>
        <tr><th>PHP 版本</th><td><?= PHP_VERSION ?></td></tr>
      </table>
      <p class="dim" style="margin-top:10px">若需修改 APP_ID、站点名称、数据库等，请直接编辑 <code>includes/config.php</code>。</p>
    </div>
  </div>

  <div class="panel">
    <div class="panel-hd">修改管理员密码</div>
    <div class="panel-bd">
      <form method="post" class="form-v">
        <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
        <input type="hidden" name="act" value="change_pwd">
        <div class="field"><label>当前密码</label><input name="cur" type="password" required></div>
        <div class="field"><label>新密码</label><input name="new" type="password" required minlength="6"></div>
        <button class="btn" type="submit">保存</button>
      </form>
    </div>
  </div>
</div>

<div class="panel">
  <div class="panel-hd">
    🔑 RSA 公钥（需完整复制到 iOS <code>PCAuthManager.m</code> 的 <code>kPCAuthPubKeyPEM</code>）
    <button class="btn btn-sm" style="float:right" onclick="copyPub()">📋 复制公钥</button>
  </div>
  <div class="panel-bd">
    <textarea id="pubArea" class="codebox" rows="10" readonly><?= htmlspecialchars($pub) ?></textarea>
    <p class="dim" style="margin-top:8px">⚠️ 私钥位于 <code>keys/private.pem</code>，请严格保密，切勿提交到公开仓库或泄露。</p>
  </div>
</div>

<script>
function copyPub(){
  var ta = document.getElementById('pubArea'); ta.select();
  document.execCommand('copy');
  alert('公钥已复制');
}
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
