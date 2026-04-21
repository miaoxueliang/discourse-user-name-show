import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const LOG_PREFIX = "[eeo-user-name-show]";
const TARGET_PREFIXES = [
  "/admin/users/list/active",
  "/admin/users/list/new",
  "/admin/users/list/staff",
  "/admin/users/list/suspended",
];

const nameCache = new Map();

function debugLog(...args) {
  try {
    if (window.localStorage && window.localStorage.eeoUserNameShowDebug === "0") {
      return;
    }
  } catch (e) {
    // ignore
  }

  // eslint-disable-next-line no-console
  console.log(LOG_PREFIX, ...args);
}

function isTargetUrl(url) {
  const value = String(url || "");
  return TARGET_PREFIXES.some((prefix) => value.indexOf(prefix) !== -1);
}

function isTargetPage() {
  return isTargetUrl(window.location.pathname);
}

function tNameLabel() {
  try {
    const lang = (document.documentElement.lang || "").toLowerCase();
    return lang.startsWith("zh") ? "姓名" : "Name";
  } catch (e) {
    return "Name";
  }
}

function tNoName() {
  try {
    const lang = (document.documentElement.lang || "").toLowerCase();
    return lang.startsWith("zh") ? "（未设置）" : "(no name)";
  } catch (e) {
    return "(no name)";
  }
}

function tI18n(key) {
  try {
    return i18n(key);
  } catch (e) {
    return null;
  }
}

function ensureExtraStyles() {
  if (document.getElementById("eeo-user-name-show-style")) {
    return;
  }

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
}

function findUsersList() {
  const lists = document.querySelectorAll(".users-list-container .users-list");
  debugLog("users-list candidates:", lists.length);

  for (const listEl of lists) {
    const rows = listEl.querySelectorAll(".directory-table__row.user");
    if (rows.length > 0) {
      debugLog("picked users-list, rows:", rows.length);
      return listEl;
    }
  }

  debugLog("no users-list found");
  return null;
}

function ensureNameHeader(listEl) {
  const header = listEl.querySelector(".directory-table__column-header-wrapper");
  if (!header) {
    debugLog("header wrapper not found");
    return;
  }

  if (header.querySelector(".directory-table__column-header.eeo-name-col-header")) {
    return;
  }

  const col = document.createElement("div");
  col.className = "directory-table__column-header eeo-name-col-header";
  col.textContent = tNameLabel();

  const lastCol = header.lastElementChild;
  if (lastCol) {
    header.insertBefore(col, lastCol);
  } else {
    header.appendChild(col);
  }

  debugLog("header inserted", col.textContent);
}

function ensureGridColumns(listEl) {
  // 读取 Discourse 已设定的 grid 模板，在末尾追加一列，而非整体替换
  const existing = listEl.style.gridTemplateColumns || "";
  if (!existing) {
    debugLog("grid template: no existing style, skip");
    return;
  }

  if (existing.indexOf("eeo-added") !== -1) {
    return; // 已追加过
  }

  // 追加一列 minmax(120px, 1fr)，并打上标记（写入 dataset 避免字符串污染）
  if (listEl.dataset.eeoColAdded) {
    return;
  }

  const newTemplate = existing + " minmax(120px, 1fr)";
  listEl.style.gridTemplateColumns = newTemplate;
  listEl.dataset.eeoColAdded = "1";
  debugLog("grid template appended:", newTemplate);
}

async function fetchNameByUserId(userId) {
  if (nameCache.has(userId)) {
    return nameCache.get(userId);
  }

  try {
    debugLog("request /admin/users/:id.json", userId);
    const data = await ajax(`/admin/users/${encodeURIComponent(userId)}.json`);
    const name = (data && (data.name || (data.user && data.user.name))) || "";
    nameCache.set(userId, name);
    return name;
  } catch (error) {
    debugLog("request failed", userId, error && error.message ? error.message : error);
    nameCache.set(userId, "");
    return "";
  }
}

async function injectNameForRow(row) {
  const userId = row.getAttribute("data-user-id");
  if (!userId) {
    return;
  }

  const usernameCell = row.querySelector(".directory-table__cell.username");
  if (!usernameCell) {
    return;
  }

  let nameCell = row.querySelector(".directory-table__cell.eeo-name-col");
  if (!nameCell) {
    nameCell = document.createElement("div");
    nameCell.className = "directory-table__cell eeo-name-col";

    const label = document.createElement("span");
    label.className = "directory-table__label";
    const labelInner = document.createElement("span");
    labelInner.textContent = tNameLabel();
    label.appendChild(labelInner);
    nameCell.appendChild(label);

    const value = document.createElement("span");
    value.className = "directory-table__value admin-user-real-name";
    nameCell.appendChild(value);

    usernameCell.insertAdjacentElement("afterend", nameCell);
  }

  let valueEl = nameCell.querySelector(".directory-table__value.admin-user-real-name");
  if (!valueEl) {
    valueEl = document.createElement("span");
    valueEl.className = "directory-table__value admin-user-real-name";
    nameCell.appendChild(valueEl);
  }

  const name = await fetchNameByUserId(userId);
  const displayName = name || tNoName();

  valueEl.textContent = displayName;
  valueEl.title = `${tNameLabel()}: ${displayName}`;
}

function injectAllRows() {
  if (!isTargetPage()) {
    return;
  }

  debugLog("injectAllRows start", window.location.pathname);

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

function startObserver() {
  let timer = null;

  const observer = new MutationObserver((mutations) => {
    if (!isTargetPage()) {
      return;
    }

    const changed = mutations.some((m) => m.addedNodes && m.addedNodes.length > 0);
    if (!changed) {
      return;
    }

    clearTimeout(timer);
    timer = setTimeout(injectAllRows, 120);
  });

  observer.observe(document.body, { childList: true, subtree: true });
  debugLog("mutation observer started");
}

export default apiInitializer("1.8.0", (api) => {
  debugLog("initializer loaded", {
    pathname: window.location.pathname,
    href: window.location.href,
  });

  api.onPageChange((url) => {
    const isTarget = isTargetUrl(url);
    debugLog("onPageChange", { url, isTarget });

    if (isTarget) {
      setTimeout(injectAllRows, 300);
    }
  });

  startObserver();
  setTimeout(injectAllRows, 500);
});