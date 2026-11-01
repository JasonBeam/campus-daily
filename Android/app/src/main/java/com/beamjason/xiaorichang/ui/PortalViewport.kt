package com.beamjason.xiaorichang.ui

import android.webkit.WebView

/** Restore only the observed collapsed, visible official portal shell. This
 * changes layout dimensions; it never reads sessions or bypasses sign-in. */
internal fun restorePortalViewport(web:WebView,onRestored:()->Unit={}) {
    web.evaluateJavascript("""(()=>{
      if(location.origin!=='https://portal.gdbtu.edu.cn'||!document.body||document.readyState==='loading')return false;
      const html=document.documentElement,body=document.body;
      const roots=Array.from(body.children).filter(e=>e.tagName==='DIV');
      if(roots.length!==1||!body.innerText.trim())return false;
      const root=roots[0],style=getComputedStyle(root);
      if(style.display==='none'||style.visibility!=='visible'||Number(style.opacity)===0)return false;
      if(html.getBoundingClientRect().height>1||body.getBoundingClientRect().height>1||root.getBoundingClientRect().height>1)return false;
      const fit=()=>{const h=Math.round(innerHeight);if(h<1)return;for(const e of [html,body,root]){e.style.setProperty('height',h+'px');e.style.setProperty('min-height',h+'px');}};
      fit();addEventListener('resize',fit);
      dispatchEvent(new Event('resize'));
      return true;
    })()""") {if(it=="true")onRestored()}
}
