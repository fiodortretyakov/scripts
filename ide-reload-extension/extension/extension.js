// Reloads this window when D:\bin\auto-brightness.ps1 writes
// D:\config\auto-brightness\ide-reload-request, which it does once the IDE has given up on its
// file watcher (a reload is the only thing that resets it) and nothing is working. Polls with fs.stat
// on purpose: the IDE's own file watcher is exactly what is dead when a reload is needed.
const fs = require('fs');
const path = require('path');
const vscode = require('vscode');

// D:\config since 8 October 2026 (migrate-prep.ps1), the same path auto-brightness.ps1 writes.
const REQUEST = path.join('D:\\config', 'auto-brightness', 'ide-reload-request');

function activate(context) {
  // Only a request written after this window loaded counts, so a reload never loops.
  const loadedAt = Date.now();
  const timer = setInterval(() => {
    fs.stat(REQUEST, (err, st) => {
      if (err || st.mtimeMs <= loadedAt) return;
      clearInterval(timer);
      vscode.commands.executeCommand('workbench.action.reloadWindow');
    });
  }, 30000);
  context.subscriptions.push({ dispose: () => clearInterval(timer) });
}

module.exports = { activate, deactivate() {} };
