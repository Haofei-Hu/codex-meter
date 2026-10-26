'use strict';
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('meter', {
  subscribe(callback) { const listener = (_event, value) => callback(value); ipcRenderer.on('meter:state', listener); ipcRenderer.invoke('meter:snapshot').then(callback); return () => ipcRenderer.removeListener('meter:state', listener); },
  action: name => ipcRenderer.invoke('meter:action', name),
  preference: (key, value) => ipcRenderer.invoke('meter:preference', key, value),
  resize: size => ipcRenderer.send('meter:resize', size)
});
