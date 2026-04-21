import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import I18n from "I18n";

// 目标路径前缀列表（active / new / staff / suspended / silenced / staged）
const TARGET_PREFIXES = [
  "/admin/users/list/active",
  "/admin/users/list/new",
  "/admin/users/list/staff",
  "/admin/users/list/suspended",
  "/admin/users/list/silenced",
  "/admin/users/list/staged",
];

// 用户名 → name 内存缓存，避免重复请求
const nameCache = new Map();

function isTargetPage() {
  const path = window.location.pathname;
  return TARGET_PREFIXES.some((prefix) => path.startsWith(prefix));
}

/**
 * 请求单个用户的 name，带缓存
 */
async function fetchUserName(username) {
  if (nameCache.has(username)) {
    return nameCache.get(username);
  }
  try {
    const data = await ajax(`/u/${username}.json`);
    const name = data?.user?.name || "";
    nameCache.set(username, name);
    return name;
  } catch {
    nameCache.set(username, "");
    return "";
  }
}

/**
 * 对单行 <tr> 注入 name 标签（幂等）
 */
async function injectNameForRow(row) {
  if (row.dataset.nameInjected) return;
  row.dataset.nameInjected = "1";

  // 兼容两种可能的列结构：带 class="username" 的 td，或第一个 td
  const link =
    row.querySelector("td.username a") ||
    row.querySelector("td:first-child a");
  if (!link) return;

  // 从 href 提取用户名，例：/admin/users/123/eeo02529
  const href = link.getAttribute("href") || "";
  const match = href.match(/\/admin\/users\/\d+\/([^/?#]+)/);
  if (!match) return;

  const username = match[1];
  const name = await fetchUserName(username);

  const td = link.closest("td");
  if (!td || td.querySelector(".admin-user-real-name")) return;

  const noName = I18n.t("user_name_show.no_name");
  const displayName = name || noName;

  const nameEl = document.createElement("div");
  nameEl.className = "admin-user-real-name";
  nameEl.title =
    I18n.t("user_name_show.name_label") + ": " + displayName;
  nameEl.textContent = displayName;
  td.appendChild(nameEl);
}

/**
 * 扫描当前页面所有用户行
 */
function injectAllRows() {
  if (!isTargetPage()) return;

  // Discourse 后台用户列表常见选择器
  const rows = document.querySelectorAll(
    [
      ".admin-users-list table tbody tr",
      ".users-list-container table tbody tr",
      "table.admin-list tbody tr",
    ].join(", ")
  );

  rows.forEach((row) => injectNameForRow(row));
}

/**
 * MutationObserver 监听 DOM 变化，处理分页 / 动态加载
 */
function startObserver() {
  let timer = null;

  const observer = new MutationObserver((mutations) => {
    if (!isTargetPage()) return;
    const hasAddedNodes = mutations.some((m) => m.addedNodes.length > 0);
    if (!hasAddedNodes) return;

    // 防抖：合并短时间内的多次触发
    clearTimeout(timer);
    timer = setTimeout(injectAllRows, 120);
  });

  observer.observe(document.body, { childList: true, subtree: true });
  return observer;
}

export default apiInitializer("1.8.0", (api) => {
  // Ember 路由切换时触发
  api.onPageChange((url) => {
    const isTarget = TARGET_PREFIXES.some((prefix) => url.startsWith(prefix));
    if (isTarget) {
      // 等待 Ember 渲染完成后再注入
      setTimeout(injectAllRows, 350);
    }
  });

  // 监听分页/筛选导致的 DOM 变化
  startObserver();

  // 页面初次加载兜底
  setTimeout(injectAllRows, 500);
});
