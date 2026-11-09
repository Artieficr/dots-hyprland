.pragma library

// Obsidian Tasks plugin (emoji format): parsing, writing, status changes, recurrence and the
// sidebar's daily-note queries. Pure functions on "YYYY-MM-DD" date strings.

const DATE_FIELDS = [["➕", "created"], ["🛫", "start"], ["⏳", "scheduled"], ["📅", "due"], ["❌", "cancelled"], ["✅", "done"]];
const PRIORITIES = [["🔺", "highest"], ["⏫", "high"], ["🔼", "medium"], ["🔽", "low"], ["⏬", "lowest"]];
const PRIORITY_RANK = { "highest": 0, "high": 1, "medium": 2, "none": 3, "low": 4, "lowest": 5 };
const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const DEFAULT_SETTINGS = {
    globalFilter: "#task",
    setCreatedDate: true,
    setDoneDate: true,
    setCancelledDate: true,
    recurrenceOnNextLine: false,
    removeScheduledDateOnRecurrence: false,
    statuses: [
        { symbol: " ", name: "Todo", type: "TODO", nextStatusSymbol: "x" },
        { symbol: "/", name: "In Progress", type: "IN_PROGRESS", nextStatusSymbol: "x" },
        { symbol: "x", name: "Done", type: "DONE", nextStatusSymbol: " " },
        { symbol: "-", name: "Cancelled", type: "CANCELLED", nextStatusSymbol: " " },
    ],
};

// Tasks plugin data.json -> settings used here. Core statuses come first, duplicates dropped.
function settingsFromPluginData(data) {
    const s = Object.assign({}, DEFAULT_SETTINGS);
    for (const key of ["globalFilter", "setCreatedDate", "setDoneDate", "setCancelledDate", "recurrenceOnNextLine", "removeScheduledDateOnRecurrence"]) {
        if (data[key] !== undefined) s[key] = data[key];
    }
    const all = [...(data.statusSettings?.coreStatuses ?? []), ...(data.statusSettings?.customStatuses ?? [])];
    const seen = {};
    const statuses = all.filter(st => st.type !== "NON_TASK" && !seen[st.symbol] && (seen[st.symbol] = true))
        .map(st => ({ symbol: st.symbol, name: st.name, type: st.type, nextStatusSymbol: st.nextStatusSymbol }));
    if (statuses.length > 0) s.statuses = statuses;
    return s;
}

function statusOf(symbol, settings) {
    return settings.statuses.find(st => st.symbol === symbol)
        ?? { symbol: symbol, name: symbol, type: symbol === "x" || symbol === "X" ? "DONE" : "TODO", nextStatusSymbol: "x" };
}

function isOpen(task, settings) {
    const type = statusOf(task.status, settings).type;
    return type === "TODO" || type === "IN_PROGRESS";
}

// Dates
function pad(n) { return n.toString().padStart(2, "0"); }
function formatDate(d) { return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; }
function toUtc(date) { const [y, m, d] = date.split("-").map(Number); return new Date(Date.UTC(y, m - 1, d)); }
function addDays(date, n) { const d = toUtc(date); d.setUTCDate(d.getUTCDate() + n); return formatDate(d); }
function daysBetween(a, b) { return Math.round((toUtc(b) - toUtc(a)) / 86400000); }
function weekday(date) { return toUtc(date).getUTCDay(); }
function daysInMonth(y, m) { return new Date(Date.UTC(y, m + 1, 0)).getUTCDate(); } // m is 0-based
function localToday() { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

// Date input like the Tasks modal: YYYY-MM-DD, today, tomorrow, yesterday, a weekday name, +3d, +2w, +1m. "" = no date
function parseDateInput(text, today) {
    const t = text.trim().toLowerCase();
    if (t === "") return "";
    if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return formatDate(toUtc(t)) === t ? t : null;
    if (t === "today") return today;
    if (t === "tomorrow") return addDays(today, 1);
    if (t === "yesterday") return addDays(today, -1);
    const wd = WEEKDAYS.indexOf(t.replace(/^next /, ""));
    if (wd >= 0) return addDays(today, ((wd - weekday(today) + 6) % 7) + 1);
    const m = t.match(/^\+?(\d+) ?([dwm])$/);
    if (m) return m[2] === "m" ? addMonths(today, Number(m[1]), null) : addDays(today, Number(m[1]) * (m[2] === "w" ? 7 : 1));
    return null;
}

// Adds months; day = null keeps the date's day, -1 = last day. Clamps to the month's length.
function addMonths(date, n, day) {
    const d = toUtc(date);
    const y = d.getUTCFullYear(), m = d.getUTCMonth() + n;
    const len = daysInMonth(y, m);
    const target = day === -1 ? len : Math.min(day ?? d.getUTCDate(), len);
    return formatDate(new Date(Date.UTC(y, m, target)));
}

// Parsing
function escapeRegExp(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

function parseLine(line, lineIndex, settings) {
    const m = line.match(/^(\s*)([-*+]|\d+[.)]) \[(.)\] ?(.*)$/);
    if (!m) return null;
    if (settings.globalFilter && !new RegExp(`(^|\\s)${escapeRegExp(settings.globalFilter)}(\\s|$)`).test(m[4])) return null;
    const task = {
        line: lineIndex, raw: line, indent: m[1], marker: m[2], status: m[3],
        description: "", priority: "none", recurrence: "", onCompletion: "", id: "", dependsOn: "", blockLink: "",
        created: "", start: "", scheduled: "", due: "", cancelled: "", done: "",
    };
    let rest = m[4];
    const block = rest.match(/\s+(\^[a-zA-Z0-9-]+)$/);
    if (block) { task.blockLink = block[1]; rest = rest.slice(0, block.index); }

    // Like the Tasks plugin: peel fields off the end; tags found among them go back to the description
    const trailingTags = [];
    let matched = true;
    while (matched) {
        matched = false;
        rest = rest.replace(/\s+$/, "");
        let f;
        for (const [emoji, key] of DATE_FIELDS) {
            if ((f = rest.match(new RegExp(`${emoji}\\uFE0F? *(\\d{4}-\\d{2}-\\d{2})$`)))) { task[key] = f[1]; rest = rest.slice(0, f.index); matched = true; }
        }
        for (const [emoji, key] of PRIORITIES) {
            if ((f = rest.match(new RegExp(`${emoji}\\uFE0F?$`)))) { task.priority = key; rest = rest.slice(0, f.index); matched = true; }
        }
        if ((f = rest.match(/🔁️? *([a-zA-Z0-9, !]+)$/))) { task.recurrence = f[1].trim(); rest = rest.slice(0, f.index); matched = true; }
        if ((f = rest.match(/🏁️? *([a-zA-Z]+)$/))) { task.onCompletion = f[1]; rest = rest.slice(0, f.index); matched = true; }
        if ((f = rest.match(/🆔️? *([a-zA-Z0-9_-]+)$/))) { task.id = f[1]; rest = rest.slice(0, f.index); matched = true; }
        if ((f = rest.match(/⛔️? *([a-zA-Z0-9_-]+( *, *[a-zA-Z0-9_-]+)*)$/))) { task.dependsOn = f[1].replace(/ /g, ""); rest = rest.slice(0, f.index); matched = true; }
        if ((f = rest.match(/(^|\s)(#[^\s#]+)$/)) && rest.length > f[0].length) {
            const before = rest.slice(0, f.index).replace(/\s+$/, "");
            if (/(🔺|⏫|🔼|🔽|⏬|🔁|🏁|🆔|⛔|➕|🛫|⏳|📅|❌|✅)/.test(before)) { trailingTags.unshift(f[2]); rest = before; matched = true; }
        }
    }
    task.description = [rest.trim(), ...trailingTags].join(" ").trim();
    return task;
}

function parseFile(text, settings) {
    const tasks = [];
    text.split("\n").forEach((line, i) => {
        const t = parseLine(line, i, settings);
        if (t) tasks.push(t);
    });
    return tasks;
}

function serialize(task) {
    let s = `${task.indent}${task.marker} [${task.status}] ${task.description}`;
    if (task.id) s += ` 🆔 ${task.id}`;
    if (task.dependsOn) s += ` ⛔ ${task.dependsOn}`;
    const p = PRIORITIES.find(([, key]) => key === task.priority);
    if (p) s += ` ${p[0]}`;
    if (task.recurrence) s += ` 🔁 ${task.recurrence}`;
    if (task.onCompletion) s += ` 🏁 ${task.onCompletion}`;
    for (const [emoji, key] of DATE_FIELDS) if (task[key]) s += ` ${emoji} ${task[key]}`;
    if (task.blockLink) s += ` ${task.blockLink}`;
    return s;
}

// Recurrence: every [N] day/week/month/year[s], every week on <weekdays>, every <weekdays>,
// every weekday, every month on the Nth/last, each optionally "when done". null = not supported.
function parseRule(text) {
    let t = text.trim().toLowerCase().replace(/\s+/g, " ");
    const whenDone = / when done$/.test(t);
    t = t.replace(/ when done$/, "");
    const days = s => {
        const list = s.split(/ *(?:,|\band\b) */).filter(x => x).map(x => WEEKDAYS.indexOf(x.replace(/s$/, "")));
        return list.length > 0 && list.every(i => i >= 0) ? list : null;
    };
    if (t === "every weekday") return { unit: "week", interval: 1, weekdays: [1, 2, 3, 4, 5], whenDone };
    let m = t.match(/^every (?:(\d+) )?(day|week|month|year)s?(?: on (.+))?$/);
    if (m) {
        const rule = { unit: m[2], interval: Number(m[1] ?? 1), whenDone };
        if (m[3] === undefined) return rule;
        if (rule.unit === "week") return (rule.weekdays = days(m[3])) ? rule : null;
        const dm = m[3].match(/^the (?:(\d+)(?:st|nd|rd|th)|(last))$/);
        if (rule.unit === "month" && dm) { rule.dayOfMonth = dm[2] ? -1 : Number(dm[1]); return rule; }
        return null;
    }
    if ((m = t.match(/^every (.+)$/))) {
        const wd = days(m[1]);
        return wd ? { unit: "week", interval: 1, weekdays: wd, whenDone } : null;
    }
    return null;
}

// First occurrence strictly after `from`
function nextOccurrence(rule, from) {
    if (rule.unit === "day") return addDays(from, rule.interval);
    if (rule.unit === "year") return addMonths(from, 12 * rule.interval, null);
    if (rule.unit === "week") {
        if (!rule.weekdays) return addDays(from, 7 * rule.interval);
        const monday = addDays(from, -((weekday(from) + 6) % 7));
        for (let d = addDays(from, 1); d <= addDays(monday, 6); d = addDays(d, 1)) if (rule.weekdays.includes(weekday(d))) return d;
        const nextMonday = addDays(monday, 7 * rule.interval);
        for (let i = 0; i < 7; i++) if (rule.weekdays.includes(weekday(addDays(nextMonday, i)))) return addDays(nextMonday, i);
    }
    if (rule.unit === "month") {
        if (rule.dayOfMonth === undefined) return addMonths(from, rule.interval, null);
        const sameMonth = addMonths(from, 0, rule.dayOfMonth);
        return sameMonth > from ? sameMonth : addMonths(from, rule.interval, rule.dayOfMonth);
    }
    return null;
}

// The next copy of a recurring task, or null if its rule isn't supported
function nextRecurrence(task, today, settings) {
    const rule = parseRule(task.recurrence);
    if (!rule) return null;
    const next = Object.assign({}, task, { status: settings.statuses.find(st => st.type === "TODO")?.symbol ?? " ", done: "", cancelled: "" });
    if (settings.setCreatedDate) next.created = today;
    const ref = task.due || task.scheduled || task.start;
    if (ref) {
        const shift = daysBetween(ref, nextOccurrence(rule, rule.whenDone ? today : ref));
        for (const key of ["start", "scheduled", "due"]) if (task[key]) next[key] = addDays(task[key], shift);
    }
    if (settings.removeScheduledDateOnRecurrence) next.scheduled = "";
    return next;
}

// New status for a task. Returns the replacement lines (a completed recurring task becomes two),
// or null if it's recurring with an unsupported rule.
function withStatus(task, symbol, today, settings) {
    const fromType = statusOf(task.status, settings).type;
    const toType = statusOf(symbol, settings).type;
    const updated = Object.assign({}, task, { status: symbol });
    if (toType !== "DONE") updated.done = "";
    if (toType !== "CANCELLED") updated.cancelled = "";
    if (toType === "DONE" && fromType !== "DONE" && settings.setDoneDate) updated.done = today;
    if (toType === "CANCELLED" && fromType !== "CANCELLED" && settings.setCancelledDate) updated.cancelled = today;
    if (toType === "DONE" && fromType !== "DONE" && task.recurrence) {
        const next = nextRecurrence(task, today, settings);
        if (!next) return null;
        return settings.recurrenceOnNextLine ? [serialize(updated), serialize(next)] : [serialize(next), serialize(updated)];
    }
    return [serialize(updated)];
}

// Checkbox click: the status's "next" symbol
function toggled(task, today, settings) {
    return withStatus(task, statusOf(task.status, settings).nextStatusSymbol, today, settings);
}

// A new task line from fields (description without the global filter)
function newTaskLine(fields, today, settings) {
    const filter = settings.globalFilter ? `${settings.globalFilter} ` : "";
    return serialize(Object.assign({
        indent: "", marker: "-", status: settings.statuses.find(st => st.type === "TODO")?.symbol ?? " ",
        priority: "none", recurrence: "", onCompletion: "", id: "", dependsOn: "", blockLink: "",
        created: settings.setCreatedDate ? today : "", start: "", scheduled: "", due: "", cancelled: "", done: "",
    }, fields, { description: filter + fields.description.trim() }));
}

// Description for editing without the global filter, and back
function editableDescription(task, settings) {
    if (!settings.globalFilter) return task.description;
    return task.description.replace(new RegExp(`(^|\\s)${escapeRegExp(settings.globalFilter)}(?=\\s|$)`), "$1").replace(/\s+/g, " ").trim();
}
function withEditedFields(task, fields, settings) {
    const filter = settings.globalFilter && !fields.description.includes(settings.globalFilter) ? `${settings.globalFilter} ` : "";
    return serialize(Object.assign({}, task, fields, { description: filter + fields.description.trim() }));
}

// Display: <mark class="c">[x]</mark> -> labels, [[note|alias]] -> alias, <br> -> line break,
// tags hidden (like "hide tags"). **bold** and *italic* are kept for the list to style
function displayParts(description) {
    const labels = [];
    let text = description.replace(/<mark class="([^"]*)">([\s\S]*?)<\/mark>/g, (_, color, inner) => {
        labels.push({ color: color, text: inner.replace(/^\[|\]$/g, "") });
        return " ";
    });
    text = text.replace(/\[\[([^\]|]*)\|([^\]]*)\]\]/g, "$2")
        .replace(/\[\[([^\]]*)\]\]/g, (_, link) => link.replace("#", " > "))
        .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/<br\s*\/?>/gi, "\n")
        .replace(/(^|\s)#[^\s#<]+/g, "$1")
        .split("\n").map(line => line.replace(/\s+/g, " ").trim()).filter(line => line).join("\n");
    return { labels: labels, text: text };
}

// One line without Markdown markers, e.g. for the clock popup
function plainText(description) {
    return displayParts(description).text.replace(/\*\*(.+?)\*\*/g, "$1").replace(/(^|[^*])\*([^*]+)\*/g, "$1$2").replace(/\n/g, " ");
}

function tagsOf(task) { return (task.description.match(/#[^\s#<]+/g) ?? []).map(t => t.toLowerCase()); }
function hasTag(task, part) { return tagsOf(task).some(t => t.includes(part)); }

// The daily note's queries: Reminders, Today, Overdue, Unscheduled, Done/Cancelled today.
// Upcoming = every other open task, so everything stays reachable.
function sections(tasks, today, settings) {
    const open = tasks.filter(t => isOpen(t, settings));
    const todayRule = t => t.due === today || t.scheduled === today || (t.scheduled && t.scheduled <= today && (!t.due || t.due > today));
    const dateKey = t => t.due || t.scheduled || t.start || "9999";
    const byDate = (a, b) => (dateKey(a) < dateKey(b) ? -1 : dateKey(a) > dateKey(b) ? 1 : 0)
        || PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority] || a.line - b.line;
    const reminders = open.filter(t => todayRule(t) && hasTag(t, "reminder")).sort(byDate);
    const todayList = open.filter(t => todayRule(t) && !hasTag(t, "quest") && !hasTag(t, "reminder")).sort(byDate);
    const overdue = open.filter(t => t.due && t.due < today && !hasTag(t, "quest")).sort(byDate);
    const unscheduled = open.filter(t => !t.scheduled && !t.start && !hasTag(t, "quest")).sort(byDate);
    const shown = new Set([...reminders, ...todayList, ...overdue, ...unscheduled]);
    const upcoming = open.filter(t => !shown.has(t)).sort((a, b) => {
        const da = [a.start, a.scheduled, a.due].filter(x => x).sort()[0] ?? "9999";
        const db = [b.start, b.scheduled, b.due].filter(x => x).sort()[0] ?? "9999";
        return da < db ? -1 : da > db ? 1 : a.line - b.line;
    });
    const done = tasks.filter(t => !isOpen(t, settings) && (t.done === today || t.cancelled === today) && !hasTag(t, "quest"));
    return { reminders: reminders, today: todayList, overdue: overdue, unscheduled: unscheduled, upcoming: upcoming, done: done };
}
