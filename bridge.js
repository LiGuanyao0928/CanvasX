// 统一封装"网页调原生代码"这件事——页面自己的逻辑不用关心究竟跑在 Mac 的
// WKWebView 还是 Windows 的 WebView2 里，两边约定同一套 JSON 消息协议
// {id, action, payload}，各自的原生 shell 负责接消息、干活、把结果传回来。
//
// 原生 shell 处理完一个请求后，调用页面里的 window.__bridgeResult(id, ok, data)
// 把结果送回来——ok=true 时 data 是返回值，ok=false 时 data 是错误信息字符串。

const NativeBridge = (() => {
  let seq = 0;
  const pending = new Map();

  window.__bridgeResult = function (id, ok, data) {
    const entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    ok ? entry.resolve(data) : entry.reject(new Error(data));
  };

  function send(action, payload) {
    return new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, reject });
      const message = { id, action, payload: payload || {} };
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) {
        window.webkit.messageHandlers.native.postMessage(message); // macOS WKWebView
      } else if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(message); // Windows WebView2
      } else {
        pending.delete(id);
        reject(new Error("原生桥接不可用（这个页面没有跑在 App 的 WebView 里）"));
      }
    });
  }

  return { send };
})();
