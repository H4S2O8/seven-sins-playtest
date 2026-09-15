const status = document.getElementById("load-state");
try {
  await import("./game.mjs");
  document.getElementById("start").disabled = false;
  document.getElementById("base").disabled = false;
  status.textContent = "准备完成 · 建议使用电脑、键盘与鼠标";
} catch (error) {
  console.error("Game initialization failed", error);
  status.textContent = "素材载入失败。请检查网络后重试；已有存档不会被删除。";
  const retry = document.getElementById("start");
  retry.disabled = false;
  retry.textContent = "重新载入";
  retry.onclick = () => location.reload();
}
