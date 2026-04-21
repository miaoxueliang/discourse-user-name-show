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

const TABLE_SELECTOR = [
  ".admin-users-list table",
  ".users-list-container table",
  "table.admin-list",
  ".admin-contents table",
].join(", ");

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
    const data = await ajax(`/u/${encodeURIComponent(username)}.json`);
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
function findUsersTable() {
  const candidates = document.querySelectorAll(TABLE_SELECTOR);
  for (const table of candidates) {
    const hasBodyRows = table.querySelector("tbody tr");
    if (hasBodyRows) {
      return table;
    }
  }
  return null;
}

function ensureNameHeader(table) {
  const headerRow = table.querySelector("thead tr");
  if (!headerRow) return -1;

  const existed = headerRow.querySelector("th.eeo-name-col");
  if (existed) {
    return Array.from(headerRow.children).indexOf(existed);
  }

  const usernameHeader =
    headerRow.querySelector("th.username") ||
    headerRow.querySelector("th:nth-child(2)") ||
    headerRow.children[1] ||
    headerRow.children[0];
  if (!usernameHeader) return -1;

  const th = document.createElement("th");
  th.className = "eeo-name-col";
  th.textContent = I18n.t("user_name_show.name_label");

  usernameHeader.insertAdjacentElement("afterend", th);
  return Array.from(headerRow.children).indexOf(th);
}

function extractUsernameFromRow(row, link) {
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

  // 兼容两种可能的列结构：带 class="username" 的 td，或第一个 td
  const link =
    row.querySelector("td.username a") ||
    row.querySelector("td:first-child a");
  if (!link) return;

  const username = extractUsernameFromRow(row, link);
  if (!username) return;

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

  const table = findUsersTable();
  if (!table) return;

  ensureNameHeader(table);

  const rows = table.querySelectorAll("tbody tr");

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
