import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import I18n from "I18n";

const LOG_PREFIX = "[eeo-user-name-show]";

// 目标路径前缀列表（active / new / staff / suspended）
const TARGET_PREFIXES = [
  "/admin/users/list/active",
  "/admin/users/list/new",
  "/admin/users/list/staff",
  "/admin/users/list/suspended",
];

// 用户名 → name 内存缓存，避免重复请求
const nameCache = new Map();

const TABLE_SELECTOR = [
  ".admin-users-list table",
  ".users-list-container table",
  "table.admin-list",
  ".admin-contents table",
].join(", ");

function debugLog(...args) {
  // 默认开启调试日志；localStorage.eeoUserNameShowDebug = "0" 可关闭
  if (window.localStorage?.eeoUserNameShowDebug === "0") {
    return;
  }
  // eslint-disable-next-line no-console
  console.log(LOG_PREFIX, ...args);
}

function isTargetUrl(url) {
  const u = String(url || "");
  return TARGET_PREFIXES.some((prefix) => u.includes(prefix));
}

function isTargetPage() {
  const path = window.location.pathname;
  return isTargetUrl(path);
}

/**
 * 请求单个用户的 name，带缓存
 */
async function fetchUserName(username) {
  if (nameCache.has(username)) {
    debugLog("cache hit", username, "=>", nameCache.get(username));
    return nameCache.get(username);
  }

  try {
    debugLog("request /u/:username.json", username);
    const data = await ajax(`/u/${encodeURIComponent(username)}.json`);
    const name = data?.user?.name || "";
    debugLog("request success", username, "=>", name || "(empty)");
    nameCache.set(username, name);
    return name;
  } catch (error) {
    debugLog("request failed", username, error?.message || error);
    nameCache.set(username, "");
    return "";
  }
}

/**
 * 对单行 <tr> 注入 name 标签（幂等）
 */
function findUserLinkInRow(row) {
  return (
    row.querySelector("a[data-user-card]") ||
    row.querySelector("a[href*='/admin/users/']") ||
    row.querySelector("a[href^='/u/']") ||
    row.querySelector("a[href*='/u/']") ||
    row.querySelector("td.username a") ||
    row.querySelector("td:first-child a")
  );
}

function findUsersTable() {
  const candidates = document.querySelectorAll(TABLE_SELECTOR);
  debugLog("table candidates by selector:", candidates.length);

  for (const table of candidates) {
    const rows = table.querySelectorAll("tbody tr");
    if (!rows.length) continue;

    const hasUserLink = Array.from(rows).some((row) => !!findUserLinkInRow(row));
    if (hasUserLink) {
      debugLog("picked table by selector, rows:", rows.length);
      return table;
    }
  }

  // 兜底：全页面扫描 table，找包含 /u/ 或 /admin/users/ 链接的表格
  const allTables = document.querySelectorAll("table");
  debugLog("fallback scanning all tables:", allTables.length);

  for (const table of allTables) {
    const rows = table.querySelectorAll("tbody tr");
    if (!rows.length) continue;

    const hasUserLink = Array.from(rows).some((row) => !!findUserLinkInRow(row));
    if (hasUserLink) {
      debugLog("picked table by fallback, rows:", rows.length);
      return table;
    }
  }

  debugLog("no users table found");
  return null;
}

function ensureNameHeader(table) {
  const headerRow = table.querySelector("thead tr");
  if (!headerRow) {
    debugLog("header row not found");
    return -1;
  }

  const existed = headerRow.querySelector("th.eeo-name-col");
  if (existed) {
    debugLog("header already exists");
    return Array.from(headerRow.children).indexOf(existed);
  }

  const usernameHeader =
    headerRow.querySelector("th.username") ||
    headerRow.querySelector("th:nth-child(2)") ||
    headerRow.children[1] ||
    headerRow.children[0];
  if (!usernameHeader) {
    debugLog("username header not found");
    return -1;
  }

  const th = document.createElement("th");
  th.className = "eeo-name-col";
  th.textContent = I18n.t("user_name_show.name_label");

  usernameHeader.insertAdjacentElement("afterend", th);
  debugLog("header inserted, title:", th.textContent);
  return Array.from(headerRow.children).indexOf(th);
}

function extractUsernameFromLink(link) {
  const href = link.getAttribute("href") || "";

  // 1) /admin/users/123/username
  const adminMatch = href.match(/\/admin\/users\/\d+\/([^/?#]+)/);
  if (adminMatch?.[1]) {
    return adminMatch[1];
  }

  // 2) /u/username 或 /u/username/summary
  const profileMatch = href.match(/\/u\/([^/?#]+)/);
  if (profileMatch?.[1]) {
    return profileMatch[1];
  }

  // 3) data-user-card 常见于用户名链接
  const userCard = link.getAttribute("data-user-card");
  if (userCard) {
    return userCard;
  }

  // 4) 兜底：链接文本
  const text = (link.textContent || "").trim();
  if (text) {
    return text;
  }

  return "";
}

async function injectNameForRow(row) {
  if (row.dataset.nameInjected === "1") return;

  const link = findUserLinkInRow(row);
  if (!link) {
    debugLog("row skipped: user link not found");
    return;
  }

  const username = extractUsernameFromLink(link);
  if (!username) {
    debugLog("row skipped: username parse failed, href:", link.getAttribute("href"));
    return;
  }

  const name = await fetchUserName(username);

  const noName = I18n.t("user_name_show.no_name");
  const displayName = name || noName;

  let nameCell = row.querySelector("td.eeo-name-col");
  if (!nameCell) {
    const usernameCell = link.closest("td");
    if (!usernameCell) return;

    nameCell = document.createElement("td");
    nameCell.className = "eeo-name-col";
    usernameCell.insertAdjacentElement("afterend", nameCell);
    debugLog("name cell inserted for", username);
  }

  let nameEl = nameCell.querySelector(".admin-user-real-name");
  if (!nameEl) {
    nameEl = document.createElement("span");
    nameEl.className = "admin-user-real-name";
    nameCell.appendChild(nameEl);
  }

  nameEl.title =
    I18n.t("user_name_show.name_label") + ": " + displayName;
  nameEl.textContent = displayName;

  // 仅在成功注入后标记，避免首轮渲染未完成导致永远不再重试
  row.dataset.nameInjected = "1";
}

/**
 * 扫描当前页面所有用户行
 */
function injectAllRows() {
  if (!isTargetPage()) return;

  debugLog("injectAllRows start, pathname:", window.location.pathname);

  const table = findUsersTable();
  if (!table) {
    debugLog("injectAllRows abort: users table not found");
    return;
  }

  ensureNameHeader(table);

  const rows = table.querySelectorAll("tbody tr");
  debugLog("rows found:", rows.length);

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
  debugLog("mutation observer started");
  return observer;
}

export default apiInitializer("1.8.0", (api) => {
  debugLog("initializer loaded", {
    pathname: window.location.pathname,
    href: window.location.href,
  });

  // Ember 路由切换时触发
  api.onPageChange((url) => {
    const isTarget = isTargetUrl(url);
    debugLog("onPageChange", { url, isTarget });

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
