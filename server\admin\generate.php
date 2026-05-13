<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$generated = [];
$batch = '';
$msg = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    pc_check_csrf();
    $type   = $_POST['type']   ?? 'day';
    $amount = (int)($_POST['amount'] ?? 1);  // 单位数量（如 3 天、7 天）
    $count  = min(1000, max(1, (int)($_POST['count'] ?? 1)));
    $note   = trim($_POST['note'] ?? '');
    $prefix = trim($_POST['prefix'] ?? '');
    $len    = max(8, min(32, (int)($_POST['len'] ?? 16)));

    $dur = pc_type_duration($type, $amount);
    $batch = 'B' . date('ymdHis') . substr(bin2hex(random_bytes(2)), 0, 4);
    $db = pc_db();
    $now = time();

    $stmt = $db->prepare("INSERT INTO ".pc_t('cards')." (card_key,type,duration,status,batch,note,created_at) VALUES (?,?,?,0,?,?,?)");
    for ($i = 0; $i < $count; $i++) {
        $tries = 0;
        do {
            $card = ($prefix ? $prefix.'-' : '') . pc_gen_card($len);
            try {
                $stmt->execute([$card, $type, $dur, $batch, $note ?: null, $now]);
                $generated[] = $card;
                break;
            } catch (PDOException $e) {
                if ($e->getCode() != 23000) throw $e; // unique 冲突
                $tries++;
                if ($tries > 5) throw $e;
            }
        } while (true);
    }
    $msg = '成功生成 '.count($generated).' 张 '.pc_type_label($type).'（时长 '.$amount.' 单位，批次 '.$batch.'）';
    pc_log('card_generate', null, null, ['batch'=>$batch, 'count'=>count($generated), 'type'=>$type, 'amount'=>$amount]);
}

$_page = 'gen';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">➕ 批量生成卡密</h1>

<?php if ($msg): ?><div class="alert ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<div class="two-col">
  <div class="panel">
    <div class="panel-hd">参数配置</div>
    <div class="panel-bd">
      <form method="post" class="form-v">
        <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
        <div class="field">
          <label>卡密类型</label>
          <div class="radio-group">
            <?php foreach (['hour'=>'小时卡','day'=>'天卡','week'=>'周卡','month'=>'月卡','year'=>'年卡','perm'=>'永久卡'] as $k=>$v): ?>
              <label class="radio"><input type="radio" name="type" value="<?= $k ?>" <?= $k==='day'?'checked':'' ?>><span><?= $v ?></span></label>
            <?php endforeach; ?>
          </div>
        </div>
        <div class="grid2">
          <div class="field"><label>时长数量 <small>（永久卡忽略）</small></label><input name="amount" type="number" min="1" max="3650" value="1"></div>
          <div class="field"><label>生成张数 <small>(1 - 1000)</small></label><input name="count" type="number" min="1" max="1000" value="10"></div>
        </div>
        <div class="grid2">
          <div class="field"><label>卡密长度</label><input name="len" type="number" min="8" max="32" value="16"></div>
          <div class="field"><label>前缀 <small>（可选）</small></label><input name="prefix" placeholder="如 VIP"></div>
        </div>
        <div class="field"><label>备注</label><input name="note" placeholder="可选"></div>
        <button class="btn" type="submit">🔨 立即生成</button>
      </form>
    </div>
  </div>
  <div class="panel">
    <div class="panel-hd">
      生成结果 <?php if ($generated): ?><small>（批次 <?= htmlspecialchars($batch) ?>）</small><?php endif; ?>
      <?php if ($generated): ?>
        <button class="btn btn-sm" style="float:right" onclick="copyAll()">📋 复制全部</button>
        <a class="btn btn-sm btn-gray" style="float:right;margin-right:8px" href="data:text/plain;charset=utf-8,<?= urlencode(implode("\n", $generated)) ?>" download="cards_<?= $batch ?>.txt">⬇️ 导出 TXT</a>
      <?php endif; ?>
    </div>
    <div class="panel-bd">
      <?php if (!$generated): ?>
        <div class="empty">左侧配置参数后点击生成</div>
      <?php else: ?>
        <textarea id="cardList" class="codebox" rows="14" readonly><?= htmlspecialchars(implode("\n", $generated)) ?></textarea>
        <p class="dim" style="margin-top:8px">共 <?= count($generated) ?> 张，点击上方复制全部或逐个点击也可</p>
      <?php endif; ?>
    </div>
  </div>
</div>
<script>
function copyAll(){
  var ta = document.getElementById('cardList');
  if (!ta) return;
  ta.select();
  document.execCommand('copy');
  alert('已复制 '+ta.value.split("\n").length+' 张到剪贴板');
}
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
