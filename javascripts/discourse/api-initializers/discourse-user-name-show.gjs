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
const nameCache = new Map(); // userId -> name

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
     * 对应 Discourse 2026.3 的 admin users 响应式列表结构：
     * .users-list (grid) -> .directory-table__column-header-wrapper + .directory-table__row
    nameCache.set(username, name);
    function findUsersList() {
      const candidates = document.querySelectorAll(".users-list-container .users-list");
      debugLog("users-list candidates:", candidates.length);

      for (const listEl of candidates) {
        const rows = listEl.querySelectorAll(".directory-table__row.user");
        if (rows.length > 0) {
          debugLog("picked users-list, rows:", rows.length);
          return listEl;
        }
      }

      debugLog("no users-list found");
      return null;
 * 对单行 <tr> 注入 name 标签（幂等）
 */
    function ensureExtraStyles() {
      if (document.getElementById("eeo-user-name-show-style")) return;

      const style = document.createElement("style");
      style.id = "eeo-user-name-show-style";
      style.textContent = `
        .users-list .directory-table__column-header.eeo-name-col-header {
          min-width: 120px;
        }

        .users-list .directory-table__cell.eeo-name-col {
          justify-content: start;
        }

        .users-list .directory-table__cell.eeo-name-col .directory-table__value {
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 220px;
          color: var(--primary-medium, #888);
        }
      `;

      document.head.appendChild(style);
    if (!rows.length) continue;

    function ensureNameHeader(listEl) {
      const header = listEl.querySelector(".directory-table__column-header-wrapper");
      if (!header) {
        debugLog("header wrapper not found");
        return;
      }

      const existed = header.querySelector(".directory-table__column-header.eeo-name-col-header");
  return null;
}
        return;
function ensureNameHeader(table) {
  const headerRow = table.querySelector("thead tr");
      const label = I18n.t("user_name_show.name_label");
      const col = document.createElement("div");
      col.className = "directory-table__column-header eeo-name-col-header";
      col.textContent = label;

      // 末列是状态图标列（空标题），将 Name 插在它之前
      const lastCol = header.lastElementChild;
      if (lastCol) {
        header.insertBefore(col, lastCol);
      } else {
        header.appendChild(col);
    return Array.from(headerRow.children).indexOf(existed);

      debugLog("header inserted, title:", label);
    }

    function ensureGridColumns(listEl) {
      const header = listEl.querySelector(".directory-table__column-header-wrapper");
      if (!header) return;

      const colCount = header.children.length;
      if (!colCount) return;

      // 首列 username 更宽，后续列等宽。colCount 包含首列。
      const template = `minmax(min-content, 2fr) repeat(${Math.max(colCount - 1, 1)}, minmax(min-content, 1fr))`;
      listEl.style.gridTemplateColumns = template;
      debugLog("grid template applied:", template);
  }

    async function fetchNameByUserId(userId) {
      if (nameCache.has(userId)) {
        debugLog("cache hit by userId", userId, "=>", nameCache.get(userId));
        return nameCache.get(userId);
      }

      try {
        debugLog("request /admin/users/:id.json", userId);
        const data = await ajax(`/admin/users/${userId}.json`);
        const name = data?.name || data?.user?.name || "";
        nameCache.set(userId, name);
        return name;
      } catch (error) {
        debugLog("request failed by userId", userId, error?.message || error);
        nameCache.set(userId, "");
        return "";
      }
  // 2) /u/username 或 /u/username/summary
  const profileMatch = href.match(/\/u\/([^/?#]+)/);
  if (profileMatch?.[1]) {
    return profileMatch[1];

      const userId = row.dataset.userId;
      if (!userId) {
        debugLog("row skipped: user id not found");
  if (text) {
    return text;
  }
      const name = await fetchNameByUserId(userId);
  return "";
}

async function injectNameForRow(row) {
      let nameCell = row.querySelector(".directory-table__cell.eeo-name-col");

        const usernameCell = row.querySelector(".directory-table__cell.username");
        if (!usernameCell) {
          debugLog("row skipped: username cell not found", userId);
          return;
        }
    debugLog("row skipped: user link not found");
        nameCell = document.createElement("div");
        nameCell.className = "directory-table__cell eeo-name-col";
        const label = document.createElement("span");
        label.className = "directory-table__label";
        label.innerHTML = `<span>${I18n.t("user_name_show.name_label")}</span>`;
        nameCell.appendChild(label);

        const value = document.createElement("span");
        value.className = "directory-table__value admin-user-real-name";
        nameCell.appendChild(value);


        debugLog("name cell inserted for userId", userId);
  if (!username) {
    debugLog("row skipped: username parse failed, href:", link.getAttribute("href"));
      let nameEl = nameCell.querySelector(".directory-table__value.admin-user-real-name");
      if (!nameEl) {
        nameEl = document.createElement("span");
        nameEl.className = "directory-table__value admin-user-real-name";
        nameCell.appendChild(nameEl);
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

  const listEl = findUsersList();
  if (!listEl) {
    debugLog("injectAllRows abort: users-list not found");
    return;
  }

  ensureExtraStyles();
  ensureNameHeader(listEl);
  ensureGridColumns(listEl);

  const rows = listEl.querySelectorAll(".directory-table__row.user");
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
