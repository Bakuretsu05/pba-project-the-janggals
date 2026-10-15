'use strict';

const store = chrome.storage.local;
const $ = id => document.getElementById(id);

async function render() {
  const {current, history = []} = await store.get(['current', 'history']);
  const alarm = await chrome.alarms.get('run');

  $('state').textContent = current
    ? `${current.kind === 'test' ? 'Test run' : 'Running'} since ${current.started_at.slice(11, 16)}: product ${current.products.length} of ${current.target_count ?? '?'}.`
    : 'Not running.';
  $('next').textContent = alarm
    ? `Next run: ${taiwanTime(alarm.scheduledTime).slice(0, 16)} (Taiwan time). Chrome must be running then.`
    : 'No more scheduled runs.';

  $('history').replaceChildren(...history.map(run => {
    const item = document.createElement('li');
    item.className = run.ok ? 'ok' : 'bad';
    item.textContent = run.line.replace(/^coupang /, '');
    const details = [run.folder, run.ping_error && `Report to Healthchecks failed: ${run.ping_error}`].filter(Boolean);
    if (details.length > 0) {
      const small = document.createElement('small');
      small.textContent = details.join(' · ');
      item.append(document.createElement('br'), small);
    }
    return item;
  }));
  if (history.length === 0) $('history').textContent = 'None yet.';
}

async function loadSettings() {
  const saved = await store.get(['pingUrl', 'pingUrlExtra']);
  $('pingUrl').value = saved.pingUrl || '';
  $('pingUrlExtra').value = saved.pingUrlExtra || '';
}

for (const button of document.querySelectorAll('button[data-command]')) {
  button.addEventListener('click', async () => {
    $('message').textContent = 'Starting...';
    const reply = await chrome.runtime.sendMessage({command: button.dataset.command});
    $('message').textContent = reply?.error || `Started. It goes on if you close this.`;
  });
}

$('save').addEventListener('click', async () => {
  await store.set({
    pingUrl: $('pingUrl').value.trim(),
    pingUrlExtra: $('pingUrlExtra').value.trim(),
  });
  $('message').textContent = 'Settings saved.';
});

chrome.storage.onChanged.addListener(render);
render();
loadSettings();
