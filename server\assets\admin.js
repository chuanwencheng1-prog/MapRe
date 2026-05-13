// 点击复制 + toast
(function(){
  var toast = document.createElement('div');
  toast.className = 'toast';
  document.body.appendChild(toast);
  var to;
  function showToast(msg){
    toast.textContent = msg;
    toast.classList.add('show');
    clearTimeout(to);
    to = setTimeout(function(){ toast.classList.remove('show'); }, 1500);
  }
  window.pcToast = showToast;

  function copyText(text){
    if (!text) return false;
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text);
      return true;
    }
    var ta = document.createElement('textarea');
    ta.value = text; ta.style.position='fixed'; ta.style.opacity='0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); document.body.removeChild(ta); return true; }
    catch(e){ document.body.removeChild(ta); return false; }
  }

  document.addEventListener('click', function(e){
    var el = e.target.closest('.copy');
    if (!el) return;
    var t = el.getAttribute('data-copy') || el.textContent.trim();
    if (copyText(t)) showToast('已复制：' + (t.length > 30 ? t.slice(0,30)+'…' : t));
  });

  // 侧边栏抽屉（移动端）
  var side = document.getElementById('pcSide');
  var mask = document.getElementById('pcSideMask');
  var btn  = document.getElementById('pcMenuBtn');
  function openSide(){ if(side){side.classList.add('show');} if(mask){mask.classList.add('show');} }
  function closeSide(){ if(side){side.classList.remove('show');} if(mask){mask.classList.remove('show');} }
  if (btn)  btn.addEventListener('click', function(e){ e.stopPropagation(); (side && side.classList.contains('show')) ? closeSide() : openSide(); });
  if (mask) mask.addEventListener('click', closeSide);
  // 点导航链接自动关闭
  document.querySelectorAll('.side nav a').forEach(function(a){ a.addEventListener('click', closeSide); });
  // 窗口变实时恢复案桌态
  window.addEventListener('resize', function(){ if (window.innerWidth > 900) closeSide(); });
})();
