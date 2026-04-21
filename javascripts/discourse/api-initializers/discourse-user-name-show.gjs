import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

const LOG_PREFIX = "[eeo-user-name-show]";
const TARGET_PREFIXES = [
  "/admin/users/list/active",
  "/admin/users/list/new",
  "/admin/users/list/staff",
  "/admin/users/list/suspended",
];

// userId (string) -> name (string)
const nameCache = new Map();
// URLs already fetched to avoid duplicate requests
const fetchedPages = new Set();

// Active name filter term
let activeNameFilter = "";
// Reference to injected filter input (reset on page change)
let filterInputEl = null;

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

    .eeo-name-filter-wrap {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      margin-left: 8px;
    }

    .eeo-name-filter-input {
      width: 150px;
      height: 32px;
      padding: 0 8px;
      border: 1px solid var(--primary-low-mid, #ccc);
      border-radius: 4px;
      font-size: 0.875em;
      background: var(--secondary, #fff);
      color: var(--primary, #333);
      vertical-align: middle;
    }

    .eeo-name-filter-input:focus {
      outline: none;
      border-color: var(--tertiary, #0076cc);
      box-shadow: 0 0 0 2px rgba(0, 118, 204, 0.2);
    }

    .eeo-name-filter-clear {
      cursor: pointer;
      color: var(--primary-medium, #888);
      font-size: 1.1em;
      line-height: 1;
      background: none;
      border: none;
      padding: 0 2px;
      display: none;
      vertical-align: middle;
    }

    .eeo-name-filter-clear.visible {
      display: inline-block;
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

/**
 * Insert the "Name" column header at the same grid position as the name data cell.
 * Data cells are inserted after the .username cell, so the header must also go
 * after the username column header (found by matching cell index).
 */
function ensureNameHeader(listEl) {
  const header = listEl.querySelector(".directory-table__column-header-wrapper");
  if (!header) {
    debugLog("header wrapper not found");
    return;
  }

  if (header.querySelector(".eeo-name-col-header")) {
    return;
  }

  // Find the index of the .username cell in the first data row
  let insertIndex = -1;
  const firstRow = listEl.querySelector(".directory-table__row.user");
  if (firstRow) {
    const cells = Array.from(firstRow.children);
    const usernameIdx = cells.findIndex((c) => c.classList.contains("username"));
    if (usernameIdx >= 0) {
      // Name data goes after username → header must also go after username header
      insertIndex = usernameIdx + 1;
    }
  }

  const col = document.createElement("div");
  col.className = "directory-table__column-header eeo-name-col-header";
  col.textContent = tNameLabel();

  const headerCols = Array.from(header.children);
  if (insertIndex >= 0 && insertIndex <= headerCols.length) {
    header.insertBefore(col, headerCols[insertIndex] || null);
  } else {
    // Fallback: insert before last column
    const lastCol = header.lastElementChild;
    header.insertBefore(col, lastCol || null);
  }

  debugLog("header inserted", col.textContent, "at index", insertIndex);
}

function ensureGridColumns(listEl) {
  if (listEl.dataset.eeoColAdded) {
    return;
  }

  const existing = listEl.style.gridTemplateColumns || "";
  if (!existing) {
    debugLog("grid template: no existing style, skip");
    return;
  }

  const newTemplate = existing + " minmax(120px, 1fr)";
  listEl.style.gridTemplateColumns = newTemplate;
  listEl.dataset.eeoColAdded = "1";
  debugLog("grid template appended:", newTemplate);
}

/**
 * Filter visible rows by name (and username) — pure client-side, no extra requests.
 * Call after injectAllRows so nameCache is populated.
 */
function applyNameFilter(term, listEl) {
  if (!listEl) {
    return;
  }

  const rows = listEl.querySelectorAll(".directory-table__row.user");
  const lowerTerm = term.toLowerCase();

  rows.forEach((row) => {
    if (!term) {
      row.style.display = "";
      return;
    }

    const userId = row.getAttribute("data-user-id");
    const name = (nameCache.get(userId) || "").toLowerCase();

    // Also match against the username shown in the row
    const usernameLink = row.querySelector(".directory-table__cell.username a");
    const username = usernameLink ? usernameLink.textContent.trim().toLowerCase() : "";

    row.style.display = name.includes(lowerTerm) || username.includes(lowerTerm) ? "" : "none";
  });
}

/**
 * Inject a "Filter by name" input next to the existing username/email search box.
 * Only injected once per page view; re-created after page navigation.
 */
function ensureNameFilter() {
  // If already injected and still in DOM, skip
  if (filterInputEl && document.contains(filterInputEl)) {
    return;
  }

  // Find the existing Discourse filter input
  const existingInput = document.querySelector(
    ".users-list-container input[type='text']"
  );
  if (!existingInput) {
    debugLog("existing filter input not found, skip name filter injection");
    return;
  }

  // Don't inject twice
  const existingWrap = document.querySelector(".eeo-name-filter-wrap");
  if (existingWrap) {
    existingWrap.remove();
  }

  const wrap = document.createElement("div");
  wrap.className = "eeo-name-filter-wrap";

  const input = document.createElement("input");
  input.type = "text";
  input.className = "eeo-name-filter-input";
  const lang = (document.documentElement.lang || "").toLowerCase();
  input.placeholder = lang.startsWith("zh") ? "按姓名筛选..." : "Filter by name...";
  input.value = activeNameFilter;
  filterInputEl = input;

  const clearBtn = document.createElement("button");
  clearBtn.className = "eeo-name-filter-clear" + (activeNameFilter ? " visible" : "");
  clearBtn.textContent = "×";
  clearBtn.title = lang.startsWith("zh") ? "清除姓名筛选" : "Clear name filter";
  clearBtn.setAttribute("type", "button");

  wrap.appendChild(input);
  wrap.appendChild(clearBtn);

  // Insert right after the existing filter input's parent container
  const parentEl = existingInput.parentElement;
  if (parentEl) {
    parentEl.insertAdjacentElement("afterend", wrap);
  } else {
    existingInput.insertAdjacentElement("afterend", wrap);
  }

  let filterTimer = null;

  input.addEventListener("input", () => {
    clearTimeout(filterTimer);
    filterTimer = setTimeout(() => {
      activeNameFilter = input.value.trim();
      clearBtn.classList.toggle("visible", !!activeNameFilter);
      const listEl = findUsersList();
      applyNameFilter(activeNameFilter, listEl);
      debugLog("name filter applied:", activeNameFilter);
    }, 200);
  });

  clearBtn.addEventListener("click", () => {
    input.value = "";
    activeNameFilter = "";
    clearBtn.classList.remove("visible");
    const listEl = findUsersList();
    applyNameFilter("", listEl);
  });

  debugLog("name filter input injected");
}

/**
 * Fetch all user names for the current page in a single request.
 * Uses the same list endpoint Discourse already calls, just adds .json suffix.
 * Results are cached by URL to avoid duplicate requests.
 */
async function fetchNamesForCurrentPage() {
  const url = window.location.pathname + ".json" + window.location.search;

  if (fetchedPages.has(url)) {
    return;
  }

  // Mark as fetching immediately to prevent concurrent duplicate requests
  fetchedPages.add(url);

  try {
    debugLog("fetch list api", url);
    const users = await ajax(url);
    if (Array.isArray(users)) {
      users.forEach((u) => {
        if (u.id != null) {
          nameCache.set(String(u.id), u.name || "");
        }
      });
      debugLog("name cache loaded", users.length, "users");
    }
  } catch (error) {
    // Remove from set so a retry is possible on next mutation
    fetchedPages.delete(url);
    debugLog("fetch list failed", error && error.message ? error.message : error);
  }
}

function injectNameForRow(row) {
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

  // Read from cache; if not yet loaded, leave empty (next mutation will repopulate)
  if (!nameCache.has(userId)) {
    return;
  }

  let valueEl = nameCell.querySelector(".directory-table__value.admin-user-real-name");
  if (!valueEl) {
    valueEl = document.createElement("span");
    valueEl.className = "directory-table__value admin-user-real-name";
    nameCell.appendChild(valueEl);
  }

  const name = nameCache.get(userId);
  const displayName = name || tNoName();
  valueEl.textContent = displayName;
  valueEl.title = `${tNameLabel()}: ${displayName}`;
}

async function injectAllRows() {
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
  ensureNameFilter();

  // One request for all users on this page — no per-user requests
  await fetchNamesForCurrentPage();

  const rows = listEl.querySelectorAll(".directory-table__row.user");
  debugLog("rows found:", rows.length);
  rows.forEach((row) => injectNameForRow(row));

  // Re-apply active name filter after names are injected
  if (activeNameFilter) {
    applyNameFilter(activeNameFilter, listEl);
  }
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
      // Reset filter input ref so it gets re-injected for the new page
      filterInputEl = null;
      setTimeout(injectAllRows, 300);
    }
  });

  startObserver();
  setTimeout(injectAllRows, 500);
});