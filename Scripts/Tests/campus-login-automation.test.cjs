const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../../App/Services/CampusWebLogin/CampusLoginAutomation.js'), 'utf8');

function run({origin = 'https://portal.gdbtu.edu.cn', pathname = '/main.html', title = '一卡通信息', destination, state = {}, window = {}, residence = ''} = {}) {
  const navigated = [];
  const parent = {__vue__: {cardInfo: {pcUrl: destination}}};
  const heading = {parentElement: parent, querySelectorAll: () => [{textContent: title}]};
  const context = {URL, JSON, window,
    location: {origin, pathname, hash: '', href: origin + pathname, assign: value => navigated.push(value)},
    document: {querySelectorAll: selector => selector === '.studentContainer-left-top-info span' ? (residence ? [{textContent:'学号：not-returned'}, {textContent:'宿舍地址：'+residence}] : []) : [heading]},
    localStorage: {getItem: () => JSON.stringify(state)}};
  return {result: JSON.parse(vm.runInNewContext(script, context)), navigated};
}

const wallet = 'https://ecykt.gdbtu.edu.cn/ykt-view/wallet/transaction';
assert.deepEqual(run({destination: wallet}).navigated, [wallet]);
for (const destination of ['https://evil.test/wallet', 'https://ecykt.gdbtu.edu.cn.evil.test/', 'http://ecykt.gdbtu.edu.cn/', 'https://user@ecykt.gdbtu.edu.cn/']) {
  const value = run({destination});
  assert.equal(value.result.stage, 'unsupported-entry');
  assert.equal(value.navigated.length, 0);
}
assert.equal(run({title: '校园卡系统', destination: wallet}).result.stage, 'waiting-portal');
assert.equal(run({destination: ''}).result.stage, 'waiting-portal');
assert.equal(run({destination: wallet, window: {__campusWalletOpening: true}}).navigated.length, 0);
const ready = {logintoken: 'fixture-token', schoolid: 'fixture-school', loginInfo: {syscustid: 'fixture-owner', custid: 'fixture-card'}};
const params = {origin: 'https://ecykt.gdbtu.edu.cn', pathname: '/ykt-view/wallet/transaction'};
assert.deepEqual(run({...params, state: ready}).result, {stage: 'wallet-ready'});
assert.equal(run({...params, state: {...ready, schoolid: undefined, loginInfo: {...ready.loginInfo, areacode: 'fixture-area'}}}).result.stage, 'wallet-ready');
assert.equal(run({...params, state: {...ready, loginInfo: {}}}).result.stage, 'waiting-wallet');
assert.equal(run({...params, pathname: '/ykt-view/', state: ready}).result.stage, 'waiting-wallet');
const residence = '示例校区2栋3号5层504房';
const profile = run({residence,destination:wallet});
assert.deepEqual(profile.result, {stage:'portal-profile',dormAddress:residence});
assert.equal(profile.navigated.length,0, 'Portal must wait for native residence capture before redirecting');
assert.deepEqual(run({residence,destination:wallet,window:{__campusDormAcknowledged:residence}}).navigated,[wallet]);
console.log('PASS: official entry, hostile URL rejection, no duplicate navigation, complete wallet identity, stage-only output');

function runSignIn(elements) {
  const context = {URL, JSON, window: {},
    location: {origin: 'https://cas.gdbtu.edu.cn', pathname: '/cas/login', hash: '', href: 'https://cas.gdbtu.edu.cn/cas/login'},
    document: {querySelector: () => null, querySelectorAll: () => elements},
    localStorage: {getItem: () => null}};
  return JSON.parse(vm.runInNewContext(script, context));
}
const visible = {getClientRects: () => [{}]}, hidden = {getClientRects: () => []};
assert.deepEqual(runSignIn([]), {stage: 'login', form: false}, 'landing page before the form stays hidden');
assert.deepEqual(runSignIn([hidden]), {stage: 'login', form: false});
assert.deepEqual(runSignIn([hidden, visible]), {stage: 'login', form: true});
console.log('PASS: sign-in form probe reports presence only');
