/* Read-only school onboarding navigation. No password fields, form listeners,
 * credentials in returned results, arbitrary link clicks or payment actions. */
JSON.stringify((() => {
  if (location.origin === 'https://cas.gdbtu.edu.cn') {
    // Presentation only: retain official inputs, encryption, captcha and MFA.
    // No field values, form submissions or authentication models are accessed.
    if (document.querySelector('.sw-login,.mobile .login-form') && !document.getElementById('campus-compact-login')) {
      const style = document.createElement('style'); style.id = 'campus-compact-login';
      style.textContent = `
        :root{--campus-bg:#f2f2f7;--campus-fg:#242428;--campus-card:#fff;--campus-line:#d9dce3;color-scheme:light dark}
        @media(prefers-color-scheme:dark){:root{--campus-bg:#000;--campus-fg:#f5f5f7;--campus-card:#1c1c1e;--campus-line:#3a3a3f}}
        html,body,#content,#vue_main,.sw-login,.sw-login-wrap{background:var(--campus-bg)!important;color:var(--campus-fg)!important;min-width:0!important}
        .sw-login-wrap>.el-container{display:block!important}
        .sw-login-wrap>.el-container>div[style]{position:relative!important;height:auto!important}
        #background,#logo{display:none!important}
        .sw-login-main{position:relative!important;top:auto!important;left:auto!important;right:auto!important;transform:none!important;width:100%!important;height:auto!important;min-height:0!important;margin:0!important;padding:16px!important;box-sizing:border-box!important}
        .sw-login-main-content{position:relative!important;max-width:440px!important;width:100%!important;margin:0 auto!important;padding:24px 20px!important;box-sizing:border-box!important;border-radius:20px!important;background:var(--campus-card)!important;box-shadow:none!important;color:var(--campus-fg)!important}
        .sw-login-menu{background:transparent!important;color:var(--campus-fg)!important}
        .sw-login-menu .el-menu-item{background:transparent!important;color:var(--campus-fg)!important;font-size:15px!important}
        .sw-login-menu .el-menu-item.is-active{color:#2670df!important;border-bottom-color:#2670df!important}
        #passwordLogin .el-input__inner,#smsCodeLogin .el-input__inner{height:50px!important;border-radius:12px!important;font-size:17px!important;background:var(--campus-bg)!important;color:var(--campus-fg)!important;border-color:var(--campus-line)!important}
        .login-btn{height:50px!important;border-radius:12px!important;background:#2169d8!important;border-color:#2169d8!important;color:#fff!important;font-size:17px!important;font-weight:600!important}
        .mobile,.mobile .wrap,.mobile .white-wrap{background:var(--campus-bg)!important;color:var(--campus-fg)!important}
        .mobile .main{max-width:472px!important;margin:0 auto!important;padding:12px 0!important}
        .mobile .card:not(.mfa-m){width:calc(100% - 32px)!important;margin:0 auto!important;padding:24px 20px!important;box-sizing:border-box!important;border-radius:20px!important;background:var(--campus-card)!important;box-shadow:none!important}
        .mobile .van-tabs__nav{background:var(--campus-card)!important}
        .mobile .van-tab{color:var(--campus-fg)!important}
        .mobile .van-tab--active{color:#2670df!important}
        .mobile .van-tabs__line{background:#2670df!important}
        .mobile .login-form .el-input__inner{height:50px!important;border-radius:12px!important;font-size:17px!important;background:var(--campus-bg)!important;color:var(--campus-fg)!important;border-color:var(--campus-line)!important}
        .mobile .login-form .el-button--primary{height:50px!important;border-radius:12px!important;background:#2169d8!important;border-color:#2169d8!important;color:#fff!important;font-size:17px!important;font-weight:600!important}
        #vue_main .card:not(.mfa-m) .el-button--primary{background:#2169d8!important;background-image:none!important;border-color:#2169d8!important;color:#fff!important;border-radius:12px!important}
        #vue_main .el-button--text{color:#2670df!important}
        #vue_main .van-tabs__line{background:#2670df!important}
        .login-error{line-height:1.5!important}
        .el-dialog{max-width:calc(100vw - 32px)!important}
      `;
      document.head.appendChild(style);
    }
    // Presence only (never values): the sign-in form or the school's own verification step is on
    // screen, so the app can stop hiding the page. Redirect/landing pages before it have neither.
    const shown = element => !!element && element.getClientRects().length > 0;
    const form = Array.from(document.querySelectorAll('input[type="password"], #passwordLogin, #smsCodeLogin, .mfa-m')).some(shown);
    return {stage:'login', form};
  }
  if (location.origin === 'https://portal.gdbtu.edu.cn') {
    // Read just the residence line of the authenticated personal-information
    // card, before leaving this origin. Never return names, student IDs or the
    // rest of the dashboard. Native code acknowledges receipt before navigation.
    const residenceLines = Array.from(document.querySelectorAll('.studentContainer-left-top-info span'));
    const residences = residenceLines
      .map(span => span.textContent.trim()).filter(text => /^宿舍地址\s*[：:]/.test(text))
      .map(text => text.replace(/^宿舍地址\s*[：:]\s*/, '').trim())
      .filter(text => text.length <= 128 && /\d/.test(text) && !/[\u0000-\u001f]/.test(text));
    const uniqueResidences = Array.from(new Set(residences));
    if (uniqueResidences.length === 1 && window.__campusDormAcknowledged !== uniqueResidences[0])
      return {stage:'portal-profile',dormAddress:uniqueResidences[0]};
    if (residenceLines.length && !uniqueResidences.length) {
      if (!window.__campusProfileWaitStarted) window.__campusProfileWaitStarted = Date.now();
      if (Date.now() - window.__campusProfileWaitStarted < 6000) return {stage:'waiting-profile'};
    }
    if (window.__campusWalletOpening) return {stage:'opening-wallet'};
    const titles = Array.from(document.querySelectorAll('.studentContainer-right-top-title'))
      .filter(title => Array.from(title.querySelectorAll('span'))
        .some(span => span.textContent.trim() === '一卡通信息'));
    if (titles.length !== 1) return {stage:'waiting-portal'};
    let element = titles[0], suppliedURL = null;
    for (let depth = 0; element && depth < 12; depth++, element = element.parentElement) {
      const component = element.__vue__;
      const info = component && (component.cardInfo || (component.$data && component.$data.cardInfo));
      if (info && typeof info.pcUrl === 'string' && info.pcUrl.trim()) { suppliedURL = info.pcUrl; break; }
    }
    if (!suppliedURL) return {stage:'waiting-portal'};
    let destination;
    try { destination = new URL(suppliedURL, location.href); } catch { return {stage:'unsupported-entry'}; }
    if (destination.origin !== 'https://ecykt.gdbtu.edu.cn' || destination.username || destination.password)
      return {stage:'unsupported-entry'};
    window.__campusWalletOpening = true;
    // The school's own component uses window.open(pcUrl). Keeping its supplied
    // URL in the current authenticated view avoids popup/extra-window handling.
    location.assign(destination.href);
    return {stage:'opening-wallet'};
  }
  if (location.origin === 'https://ecykt.gdbtu.edu.cn') {
    const walletRoute = location.pathname.startsWith('/ykt-view/wallet/') ||
      location.pathname === '/ykt-view/wallet' ||
      (location.pathname === '/ykt-view/' && /^#\/wallet(?:\/|$)/.test(location.hash));
    if (!walletRoute) return {stage:'waiting-wallet'};
    try {
      const state = JSON.parse(localStorage.getItem('elecampus_state') || '{}');
      return {stage:state.logintoken && state.loginInfo && state.loginInfo.syscustid &&
        (state.schoolid || state.loginInfo.areacode) &&
        ((state.custInfo && state.custInfo.custid) || state.loginInfo.custid || state.custid) ? 'wallet-ready' : 'waiting-wallet'};
    } catch { return {stage:'waiting-wallet'}; }
  }
  return {stage:'unsupported-origin'};
})())
