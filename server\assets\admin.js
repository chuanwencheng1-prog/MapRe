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
})();
