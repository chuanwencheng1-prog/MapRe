<?php
/**
 * 菜单配置后台
 * 功能：维护 iOS 插件的一级菜单（卡片）+ 二级菜单项（含直链 URL）
 * 数据表：pc_menus / pc_menu_items —— 若不存在自动建表，兼容老站点升级
 * iOS 端通过 api.php?action=config 拉取生效
 */
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';
pc_require_login();

$db  = pc_db();
$cfg = pc_cfg();
$msg = '';

/* ---------------- 自动建表（老站点升级兼容） ---------------- */
$pref = $cfg['db']['pref'];
$db->exec("CREATE TABLE IF NOT EXISTS `{$pref}menus` (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    app_id VARCHAR(64) NOT NULL DEFAULT 'pcui_default',
    title VARCHAR(64) NOT NULL,
    icon  VARCHAR(16) NOT NULL DEFAULT '📋',
    color VARCHAR(16) NOT NULL DEFAULT '#1677FF',
    sort  INT NOT NULL DEFAULT 0,
    status TINYINT NOT NULL DEFAULT 1,
    created_at INT UNSIGNED NOT NULL,
    INDEX idx_app (app_id, status, sort)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$db->exec("CREATE TABLE IF NOT EXISTS `{$pref}menu_items` (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    menu_id INT UNSIGNED NOT NULL,
    title VARCHAR(64) NOT NULL,
    url   VARCHAR(1024) DEFAULT NULL,
    sort  INT NOT NULL DEFAULT 0,
    status TINYINT NOT NULL DEFAULT 1,
    created_at INT UNSIGNED NOT NULL,
    INDEX idx_menu (menu_id, status, sort)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

/* ---------------- 动作处理 ---------------- */
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    pc_check_csrf();
    $act = $_POST['act'] ?? '';
    $now = time();

    try {
        if ($act === 'add_menu') {
            $title = trim($_POST['title'] ?? '');
            $icon  = trim($_POST['icon']  ?? '📋');
            $color = trim($_POST['color'] ?? '#1677FF');
            $sort  = (int)($_POST['sort'] ?? 0);
            if ($title === '') throw new Exception('菜单标题不能为空');
            $db->prepare("INSERT INTO ".pc_t('menus')." (app_id,title,icon,color,sort,status,created_at) VALUES (?,?,?,?,?,1,?)")
               ->execute([$cfg['app_id'], $title, $icon ?: '📋', $color ?: '#1677FF', $sort, $now]);
            $msg = '已添加一级菜单：' . $title;
            pc_log('menu_add', null, null, ['title'=>$title]);
        }
        elseif ($act === 'edit_menu') {
            $id    = (int)($_POST['id'] ?? 0);
            $title = trim($_POST['title'] ?? '');
            $icon  = trim($_POST['icon']  ?? '📋');
            $color = trim($_POST['color'] ?? '#1677FF');
            $sort  = (int)($_POST['sort'] ?? 0);
            $status= (int)($_POST['status'] ?? 1);
            if (!$id || $title === '') throw new Exception('参数错误');
            $db->prepare("UPDATE ".pc_t('menus')." SET title=?,icon=?,color=?,sort=?,status=? WHERE id=?")
               ->execute([$title, $icon ?: '📋', $color ?: '#1677FF', $sort, $status, $id]);
            $msg = '已更新';
            pc_log('menu_edit', null, null, ['id'=>$id]);
        }
        elseif ($act === 'del_menu') {
            $id = (int)($_POST['id'] ?? 0);
            if (!$id) throw new Exception('参数错误');
            $db->prepare("DELETE FROM ".pc_t('menu_items')." WHERE menu_id=?")->execute([$id]);
            $db->prepare("DELETE FROM ".pc_t('menus'). " WHERE id=?")->execute([$id]);
            $msg = '已删除菜单及其子项';
            pc_log('menu_del', null, null, ['id'=>$id]);
        }
        elseif ($act === 'add_item') {
            $mid   = (int)($_POST['menu_id'] ?? 0);
            $title = trim($_POST['title'] ?? '');
            $url   = trim($_POST['url']   ?? '');
            $sort  = (int)($_POST['sort'] ?? 0);
            if (!$mid || $title === '') throw new Exception('参数错误');
            $db->prepare("INSERT INTO ".pc_t('menu_items')." (menu_id,title,url,sort,status,created_at) VALUES (?,?,?,?,1,?)")
               ->execute([$mid, $title, $url ?: null, $sort, $now]);
            $msg = '已添加二级项：' . $title;
            pc_log('item_add', null, null, ['menu_id'=>$mid, 'title'=>$title]);
        }
        elseif ($act === 'edit_item') {
            $id    = (int)($_POST['id'] ?? 0);
            $title = trim($_POST['title'] ?? '');
            $url   = trim($_POST['url']   ?? '');
            $sort  = (int)($_POST['sort'] ?? 0);
            $status= (int)($_POST['status'] ?? 1);
            if (!$id || $title === '') throw new Exception('参数错误');
            $db->prepare("UPDATE ".pc_t('menu_items')." SET title=?,url=?,sort=?,status=? WHERE id=?")
               ->execute([$title, $url ?: null, $sort, $status, $id]);
            $msg = '已更新';
            pc_log('item_edit', null, null, ['id'=>$id]);
        }
        elseif ($act === 'del_item') {
            $id = (int)($_POST['id'] ?? 0);
            if (!$id) throw new Exception('参数错误');
            $db->prepare("DELETE FROM ".pc_t('menu_items')." WHERE id=?")->execute([$id]);
            $msg = '已删除二级项';
            pc_log('item_del', null, null, ['id'=>$id]);
        }
        elseif ($act === 'seed_default') {
            // 一键灌入 iOS 端原来硬编码的默认菜单，仅在表为空时执行
            $cnt = (int)$db->query("SELECT COUNT(*) FROM ".pc_t('menus')." WHERE app_id=".$db->quote($cfg['app_id']))->fetchColumn();
            if ($cnt > 0) throw new Exception('已有菜单数据，取消灌入');
            $ins1 = $db->prepare("INSERT INTO ".pc_t('menus')." (app_id,title,icon,color,sort,status,created_at) VALUES (?,?,?,?,?,1,?)");
            $ins2 = $db->prepare("INSERT INTO ".pc_t('menu_items')." (menu_id,title,url,sort,status,created_at) VALUES (?,?,?,?,1,?)");

            $ins1->execute([$cfg['app_id'], '海岛地图', '📋', '#1677FF', 1, $now]);
            $m1 = (int)$db->lastInsertId();
            $ins2->execute([$m1, '海岛除草', 'https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F4ff7550a-c7db-4e57-adc5-ad9891b13014.pak', 1, $now]);
            $ins2->execute([$m1, '海岛全除', 'https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F7c9770d3-67b4-440d-bd46-8f788663ef75.pak', 2, $now]);

            $ins1->execute([$cfg['app_id'], '上色配置', '👤', '#00B96B', 2, $now]);
            $m2 = (int)$db->lastInsertId();
            $ins2->execute([$m2, '人物上色', 'https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2Fb8a6cedb-0f50-482b-83d0-4a7d13af8de2.pak', 1, $now]);

            $msg = '已灌入默认菜单';
            pc_log('menu_seed', null, null, []);
        }
        else {
            throw new Exception('未知动作');
        }
    } catch (Exception $e) {
        $msg = '操作失败：' . $e->getMessage();
    }
}

/* ---------------- 读取列表 ---------------- */
$menus = $db->prepare("SELECT * FROM ".pc_t('menus')." WHERE app_id=? ORDER BY sort ASC, id ASC");
$menus->execute([$cfg['app_id']]);
$menus = $menus->fetchAll();

$items = [];
if ($menus) {
    $ids = implode(',', array_map(function($m){ return (int)$m['id']; }, $menus));
    $its = $db->query("SELECT * FROM ".pc_t('menu_items')." WHERE menu_id IN ($ids) ORDER BY sort ASC, id ASC")->fetchAll();
    foreach ($its as $it) $items[(int)$it['menu_id']][] = $it;
}

$_page = 'menus';
include __DIR__ . '/../includes/header.php';
?>
<h1 class="page-title">🧩 菜单配置 <small>（iOS 端远程更新 UI 菜单）</small></h1>

<?php if ($msg): ?><div class="alert <?= strpos($msg,'失败')!==false?'err':'ok' ?>"><?= htmlspecialchars($msg) ?></div><?php endif; ?>

<div class="panel">
  <div class="panel-hd">
    操作说明
    <form method="post" style="float:right;display:inline">
      <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
      <input type="hidden" name="act" value="seed_default">
      <button class="btn btn-sm btn-gray" onclick="return confirm('仅在当前 APP_ID 下无数据时执行，确定？')">🌱 灌入默认菜单</button>
    </form>
  </div>
  <div class="panel-bd">
    <p class="dim">
      一级菜单为 iOS 主界面上的卡片，二级菜单为卡片展开后的项。二级项可填写"直链"URL —— 该 URL 即 iOS 端点击"执行"按钮后下载的 pak 地址。<br>
      当前 APP_ID：<code><?= htmlspecialchars($cfg['app_id']) ?></code>（只能管理本 APP_ID 下的菜单，iOS 端拉取时也按此隔离）。所有修改保存后 iOS 端<strong>下一次启动</strong>自动拉取生效。
    </p>
  </div>
</div>

<!-- 新增一级菜单 -->
<div class="panel">
  <div class="panel-hd">➕ 新增一级菜单</div>
  <div class="panel-bd">
    <form method="post" class="form-v">
      <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
      <input type="hidden" name="act" value="add_menu">
      <div class="grid2">
        <div class="field"><label>标题</label><input name="title" placeholder="如：海岛地图" required></div>
        <div class="field"><label>排序 <small>（小的在前）</small></label><input name="sort" type="number" value="0"></div>
      </div>
      <div class="grid2">
        <div class="field"><label>图标 emoji <small>（1-2 字符，如 📋 👤 ⚙️）</small></label><input name="icon" value="📋" maxlength="4"></div>
        <div class="field"><label>图标底色 HEX <small>（#RRGGBB）</small></label><input name="color" value="#1677FF" pattern="^#[0-9A-Fa-f]{6}$"></div>
      </div>
      <button class="btn btn-primary" type="submit">创建</button>
    </form>
  </div>
</div>

<!-- 现有菜单列表 -->
<?php if (!$menus): ?>
  <div class="panel"><div class="panel-bd"><div class="empty">暂无菜单 — 先在上方新增一级菜单，或点击顶部"灌入默认菜单"</div></div></div>
<?php else: foreach ($menus as $m): $mid=(int)$m['id']; ?>
<div class="panel menu-card">
  <div class="panel-hd">
    <span class="menu-icon" style="background:<?= htmlspecialchars($m['color']) ?>"><?= htmlspecialchars($m['icon']) ?></span>
    <span class="menu-title"><?= htmlspecialchars($m['title']) ?></span>
    <small>#<?= $mid ?> · 排序 <?= (int)$m['sort'] ?> · <?= $m['status']?'启用':'<span style="color:#e74c3c">已停用</span>' ?> · <?= (int)($items[$mid]??[]?count($items[$mid]):0) ?> 个子项</small>
    <span style="float:right">
      <button class="btn btn-sm btn-gray" type="button" onclick="pcToggle('edit_menu_<?= $mid ?>')">✏️ 编辑</button>
      <button class="btn btn-sm btn-gray" type="button" onclick="pcToggle('add_item_<?= $mid ?>')">➕ 添加子项</button>
      <form method="post" style="display:inline" onsubmit="return confirm('删除一级菜单将连同其全部子项一起删除，不可恢复，确定？')">
        <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
        <input type="hidden" name="act" value="del_menu">
        <input type="hidden" name="id" value="<?= $mid ?>">
        <button class="btn btn-sm btn-danger" type="submit">🗑 删除</button>
      </form>
    </span>
  </div>

  <!-- 编辑一级菜单（默认折叠） -->
  <div class="panel-bd collapse" id="edit_menu_<?= $mid ?>" style="display:none">
    <form method="post" class="form-v">
      <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
      <input type="hidden" name="act" value="edit_menu">
      <input type="hidden" name="id" value="<?= $mid ?>">
      <div class="grid2">
        <div class="field"><label>标题</label><input name="title" value="<?= htmlspecialchars($m['title']) ?>" required></div>
        <div class="field"><label>排序</label><input name="sort" type="number" value="<?= (int)$m['sort'] ?>"></div>
      </div>
      <div class="grid2">
        <div class="field"><label>图标</label><input name="icon" value="<?= htmlspecialchars($m['icon']) ?>" maxlength="4"></div>
        <div class="field"><label>底色 HEX</label><input name="color" value="<?= htmlspecialchars($m['color']) ?>" pattern="^#[0-9A-Fa-f]{6}$"></div>
      </div>
      <div class="field"><label>状态</label>
        <select name="status">
          <option value="1" <?= $m['status']?'selected':'' ?>>启用</option>
          <option value="0" <?= !$m['status']?'selected':'' ?>>停用（对 iOS 端隐藏）</option>
        </select>
      </div>
      <button class="btn" type="submit">保存</button>
    </form>
  </div>

  <!-- 新增子项（默认折叠） -->
  <div class="panel-bd collapse" id="add_item_<?= $mid ?>" style="display:none;border-top:1px dashed #f0f2f5">
    <form method="post" class="form-v">
      <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
      <input type="hidden" name="act" value="add_item">
      <input type="hidden" name="menu_id" value="<?= $mid ?>">
      <div class="grid2">
        <div class="field"><label>子项标题</label><input name="title" placeholder="如：海岛除草" required></div>
        <div class="field"><label>排序</label><input name="sort" type="number" value="0"></div>
      </div>
      <div class="field"><label>直链 URL <small>（点击"执行"后下载 pak 的地址，可留空 → 回退 iOS 端默认）</small></label>
        <input name="url" placeholder="https://..." type="url">
      </div>
      <button class="btn btn-primary" type="submit">添加子项</button>
    </form>
  </div>

  <!-- 子项列表 -->
  <div class="panel-bd" style="padding-top:0">
    <?php if (empty($items[$mid])): ?>
      <div class="empty" style="padding:18px">该菜单暂无子项 — 点上方 ➕ 添加子项</div>
    <?php else: ?>
    <table class="tbl list sub-items">
      <thead><tr><th style="width:60px">排序</th><th>标题</th><th>直链 URL</th><th style="width:80px">状态</th><th style="width:160px">操作</th></tr></thead>
      <tbody>
      <?php foreach ($items[$mid] as $it): $iid=(int)$it['id']; ?>
        <tr>
          <td><?= (int)$it['sort'] ?></td>
          <td><?= htmlspecialchars($it['title']) ?></td>
          <td class="mono dim url-cell" title="<?= htmlspecialchars($it['url'] ?? '') ?>"><?= htmlspecialchars(mb_strimwidth((string)$it['url'],0,60,'…')) ?: '<span class="dim">（未填，回退默认）</span>' ?></td>
          <td><?= $it['status']?'<span class="pill pill-green">启用</span>':'<span class="pill pill-gray">停用</span>' ?></td>
          <td>
            <button class="btn btn-sm btn-gray" type="button" onclick="pcToggle('edit_item_<?= $iid ?>')">✏️</button>
            <form method="post" style="display:inline" onsubmit="return confirm('删除该子项？')">
              <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
              <input type="hidden" name="act" value="del_item">
              <input type="hidden" name="id" value="<?= $iid ?>">
              <button class="btn btn-sm btn-danger" type="submit">🗑</button>
            </form>
          </td>
        </tr>
        <tr id="edit_item_<?= $iid ?>" class="collapse" style="display:none">
          <td colspan="5" style="background:#fafbfc">
            <form method="post" class="form-v" style="padding:4px 0">
              <input type="hidden" name="_csrf" value="<?= pc_csrf() ?>">
              <input type="hidden" name="act" value="edit_item">
              <input type="hidden" name="id" value="<?= $iid ?>">
              <div class="grid2">
                <div class="field"><label>标题</label><input name="title" value="<?= htmlspecialchars($it['title']) ?>" required></div>
                <div class="field"><label>排序</label><input name="sort" type="number" value="<?= (int)$it['sort'] ?>"></div>
              </div>
              <div class="field"><label>直链 URL</label><input name="url" value="<?= htmlspecialchars($it['url'] ?? '') ?>" type="url" placeholder="留空 = 回退 iOS 默认"></div>
              <div class="field"><label>状态</label>
                <select name="status">
                  <option value="1" <?= $it['status']?'selected':'' ?>>启用</option>
                  <option value="0" <?= !$it['status']?'selected':'' ?>>停用</option>
                </select>
              </div>
              <button class="btn" type="submit">保存</button>
              <button class="btn btn-gray" type="button" onclick="pcToggle('edit_item_<?= $iid ?>')">取消</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
    <?php endif; ?>
  </div>
</div>
<?php endforeach; endif; ?>

<script>
function pcToggle(id){
  var el = document.getElementById(id);
  if (!el) return;
  el.style.display = (el.style.display === 'none' ? '' : 'none');
}
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
