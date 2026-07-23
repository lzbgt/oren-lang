"use strict";

const path = require("path");
const fs = require("fs");

let client;

function serverExecutableName() {
  return process.platform === "win32" ? "oren-lsp.exe" : "oren-lsp";
}

function defaultServerCommand(workspaceRoot) {
  const exe = serverExecutableName();
  if (workspaceRoot) {
    const workspaceCommand = path.join(workspaceRoot, exe);
    if (fs.existsSync(workspaceCommand)) {
      return workspaceCommand;
    }
  }
  return exe;
}

function resolveServerCommand(vscode) {
  const configured = vscode.workspace.getConfiguration("oren").get("lsp.path", "");
  if (configured && configured.trim() !== "") {
    return configured.trim();
  }
  const folders = vscode.workspace.workspaceFolders || [];
  const root = folders.length > 0 ? folders[0].uri.fsPath : "";
  return defaultServerCommand(root);
}

function activate(context) {
  const vscode = require("vscode");
  const { LanguageClient } = require("vscode-languageclient/node");
  const command = resolveServerCommand(vscode);
  const folders = vscode.workspace.workspaceFolders || [];
  const cwd = folders.length > 0 ? folders[0].uri.fsPath : undefined;
  const serverOptions = {
    command,
    args: [],
    options: cwd ? { cwd } : undefined
  };
  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "oren" }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher("**/*.oren")
    }
  };
  client = new LanguageClient("oren-lsp", "Oren Language Server", serverOptions, clientOptions);
  context.subscriptions.push(client.start());
}

function deactivate() {
  if (!client) {
    return undefined;
  }
  return client.stop();
}

module.exports = {
  activate,
  deactivate,
  defaultServerCommand,
  resolveServerCommand
};
