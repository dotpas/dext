// ==================== i18n ====================
// i18n object is now defined in i18n.js


var currentLang = localStorage.getItem("dext-lang");
if (!currentLang) {
    var browserLang = (navigator.language || navigator.userLanguage || "en").toLowerCase().split("-")[0];
    currentLang = i18n[browserLang] ? browserLang : "en";
}

function t(key) { return i18n[currentLang][key] || key; }

function applyI18n() {
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
        var key = el.getAttribute("data-i18n");
        var val = t(key);
        if ((el.tagName == "INPUT" || el.tagName == "TEXTAREA") && el.placeholder) el.placeholder = val;
        else if (el.tagName == "OPTION") el.textContent = val;
        else el.textContent = val;
    });
    // Update dynamic things
    var p = document.querySelector(".ni.on").getAttribute("data-page");
    document.getElementById("page-title").textContent = t(p);
}

function changeLang(lang) {
    currentLang = lang;
    localStorage.setItem("dext-lang", currentLang);
    document.getElementById("lang-select").value = currentLang;
    applyI18n();
}


// ==================== Dashboard Functions ====================
async function load() {
    try {
        // Sync language selector
        document.getElementById("lang-select").value = currentLang;

        var r = await Promise.all([fetch("/api/config").then(function (x) { return x.json() }), fetch("/api/projects").then(function (x) { return x.json() }),
        fetch("/api/test/summary").then(function (x) { return x.json() })]);
        cfg = r[0]; document.getElementById("env-count").textContent = cfg.environments ? cfg.environments.length : 0;
        document.getElementById("project-count").textContent = r[1].length || 0;
        var cov = r[2].available ? r[2].coverage : 0; document.getElementById("coverage-value").textContent = cov ? cov + "%" : "N/A";
        var ring = document.getElementById("cov-ring"); ring.style.strokeDasharray = Math.round(cov * 2.64) + " 264";
        envList(cfg.environments || []); act(t("data_loaded"), t("just_now"), t("done"));

        applyI18n(); // Initial translation
        var langLabel = document.getElementById("lang-label");
        if (langLabel) langLabel.textContent = currentLang.toUpperCase();

        // Restore active project if exists
        var savedPj = localStorage.getItem("activeProject");
        if (savedPj) selectActiveProject(savedPj, true);
    } catch (e) { console.error("load() dashboard error:", e); }

    // Load telemetry history independently - must not be blocked by dashboard errors
    try { loadHistory(); } catch(e) { console.warn("loadHistory error:", e); }

    // Initialize metrics charts & load metrics history
    try { initCharts(); loadMetricsHistory(); } catch(e) { console.warn("metrics init error:", e); }
}

function envList(a) {
    var l = document.getElementById("env-list"); if (!a.length) { l.innerHTML = "<li class=\"env-i\">" + t("no_env") + "</li>"; return; }
    var h = ""; for (var i = 0; i < a.length; i++) { var e = a[i]; h += "<li class=\"env-i\"><div class=\"env-nm\">" + e.name + (e.isDefault ? " <span class=\"env-bg\">Default</span>" : "") + "</div><span class=\"env-pt\">" + e.path + "</span></li>"; } l.innerHTML = h;
}

function act(a, t, s) {
    var b = document.getElementById("at-body"); var c = s == "Done" ? "st-s" : s == "Active" ? "st-p" : "st-w";
    b.innerHTML = "<tr><td>" + a + "</td><td>" + t + "</td><td><span class=\"st " + c + "\">" + s + "</span></td></tr>" + b.innerHTML;
}

async function scan() { act(t("active"), t("just_now"), t("active")); try { await fetch("/api/env/scan", { method: "POST" }); load(); act(t("done"), t("just_now"), t("done")); } catch (e) { console.error(e); } }

// Test Runner State
var trState = { total: 0, current: 0, passed: 0, failed: 0, open: false };

// Connection Logic (SignalR vs SSE)
function hub() {
    // Prefer SignalR / WebSockets (http.sys native). Fall back to SSE on failure.
    if (typeof signalR === 'undefined') {
        console.log("SignalR client missing, using SSE...");
        if (typeof window.DextSSE !== 'undefined' && window.DextSSE.connect)
            window.DextSSE.connect(function (eventName, data) {
                if (typeof window.handleSseEvent === 'function')
                    window.handleSseEvent(eventName, data);
            });
        else
            connectSSE();
        return;
    }

    var c = new signalR.HubConnectionBuilder().withUrl("/hubs/dashboard")
        .withAutomaticReconnect()
        .build();

    c.start()
        .then(function () {
            console.log("Connected via SignalR (WebSockets preferred)");
            window.__dextHub = c;
            c.on("ReceiveLog", function (l, m) {
                processLog(l, m);
            });
            c.on("DashboardEvent", function (eventName, data) {
                if (typeof window.handleSseEvent === 'function')
                    window.handleSseEvent(eventName, data);
            });
        })
        .catch(function (e) {
            console.log("SignalR failed, trying SSE fallback...", e);
            if (typeof window.DextSSE !== 'undefined' && window.DextSSE.connect)
                window.DextSSE.connect(function (eventName, data) {
                    if (typeof window.handleSseEvent === 'function')
                        window.handleSseEvent(eventName, data);
                });
            else
                connectSSE();
        });
}


function connectSSE() {
    console.log("Starting SSE Connection (Legacy)...");
    if (window.dashboardSSE) window.dashboardSSE.close();
    window.dashboardSSE = new EventSource("/events");
    var evtSource = window.dashboardSSE;

    evtSource.onopen = function () { console.log("SSE Connection Opened (Legacy)"); };
    evtSource.onerror = function (e) {
        if (e.target.readyState == EventSource.CLOSED) {
            console.log("SSE Closed. Reconnecting in 5s...");
            setTimeout(connectSSE, 5000);
        }
    };

    ["run_start", "test_start", "test_complete", "run_complete", "log"].forEach(function(evt) {
        evtSource.addEventListener(evt, function(e) {
            handleSseEvent(evt, e.data);
        });
    });
}

function handleSseEvent(eventName, data) {
    if (eventName === "metrics") {
        try {
            var payload = JSON.parse(data);
            addMetricPoint(payload);
        } catch(e) {
            console.error("Error parsing metrics SSE event:", e);
        }
        return;
    }

    if (eventName === "log" || eventName === "span") {
        try {
            var obj = JSON.parse(data);
            
            // Normalize properties (camelCase from Sidecar to snake_case for main.js)
            if (obj.traceId !== undefined) obj.trace_id = obj.traceId;
            if (obj.spanId !== undefined) obj.span_id = obj.spanId;
            if (obj.parentId !== undefined) obj.parent_id = obj.parentId;
            if (obj.dur !== undefined && obj.dur !== null) obj.duration_ms = obj.dur;
            obj.app = obj.app || "App";

            if (eventName === "log") {
                processLog(obj.lvl || "Info", obj.msg || data, obj.ts, obj.app);
                // S24: Process Distributed Tracing if log contains trace data
                if (obj.trace_id) {
                    processTrace(obj);
                }
            } else {
                // eventName === "span"
                // Map span properties for trace processor
                obj.msg = obj.name; // Use span name as message for display
                obj.lvl = obj.lvl || "Info"; 
                if (obj.trace_id) {
                   processTrace(obj);
                }
            }
        } catch(e) {
            if (eventName === "log") processLog("Info", data, null, "App");
        }
        return;
    }

    if (eventName === "run_start") {
        var d = JSON.parse(data);
        var total = d.total || d.totalTests || 0;
        trState = { total: total, current: 0, passed: 0, failed: 0, open: true };
        updateTestProgress();
    } else if (eventName === "test_complete") {
        var info = JSON.parse(data);
        trState.current++;
        var isPassed = (info.status === "Passed");
        if (isPassed) trState.passed++; else trState.failed++;
        
        var testFullName = (info.fixture ? info.fixture + "." : "") + info.test;
        var msg = (isPassed ? "Passed" : "Failed") + " Test: " + testFullName;
        processLog(isPassed ? "Info" : "Error", msg);
        updateTestProgress();
    } else if (eventName === "run_complete") {

        trState.open = false;
        updateTestProgress(true);
        renderTestTree();

    } else if (eventName === "workspace_sync") {
        try {
            var res = JSON.parse(data);
            window.lastWorkspaceScan = res;

            // Render Results
            renderScanList("scan-dproj", res.projects, "folder");
            renderScanList("scan-tests", res.tests, "science");
            renderScanList("scan-http", res.httpFiles, "http");
            renderScanList("scan-docs", res.docs, "description");

            // Populate Dropdowns
            populateSelect("header-pj-select", res.projects, "activeProject");
            // NOTE: tests-pj-select is handled exclusively by updateTestProjectsDropdown
            populateSelect("http-file-select", res.httpFiles, "activeHttpFile");

            // Clear stale test suite on new workspace sync, then rediscover all projects
            testSuite = {};
            updateTestProjectsDropdown(res);
        } catch(e) {
            console.error("Error processing workspace sync SSE event:", e);
        }
    }

    // Update Test Tree (New Feature)
    if (eventName !== "log") {
        updateTestState(eventName, JSON.parse(data));
    }
}



function processLog(level, message, timestamp, app) {
    app = app || "App";
    var logItem = { level: level, message: message, timestamp: timestamp || new Date().toISOString(), app: app };
    logStore.push(logItem);
    if (logStore.length > 1000) logStore.shift();

    if (!loadingHistory) {
        scheduleRenderLogs();
    }

    // --- Test Runner Progress Parsing (For SignalR/Log Mode) ---
    // If we are in SSE mode, this parsing is redundant but harmless as logs from SSE are synthetic here.
    // However, if we receive Raw Logs via SignalR (Sidecar), we MUST parse them here.
    if (message.indexOf("Run Started") >= 0) {
        trState = { total: 0, current: 0, passed: 0, failed: 0, open: true };
        var match = message.match(/(\d+) tests/);
        if (match) trState.total = parseInt(match[1]);
        updateTestProgress();
    } else if (trState.open && !window.sseActive) { // Only parse logs if NOT using SSE events
        if (message.indexOf("Passed Test:") >= 0) {
            trState.current++; trState.passed++;
            updateTestProgress();
        } else if (message.indexOf("Failed Test:") >= 0) {
            trState.current++; trState.failed++;
            updateTestProgress();
        } else if (message.indexOf("Skipped Test:") >= 0) {
            trState.current++;
            updateTestProgress();
        } else if (message.indexOf("Run Completed:") >= 0) {
            trState.open = false;
            updateTestProgress(true);
        }
    }

    // Update Test Tree (New Feature)
    updateTestState(message);
}

function updateTestProgress(done) {
    var el = document.getElementById("tr-status");
    if (!el) return;

    if (trState.open || done) el.style.display = "flex";
    else el.style.display = "none";


    var pct = trState.total > 0 ? (trState.current / trState.total) * 100 : 0;
    if (pct > 100) pct = 100;

    document.getElementById("tr-bar").style.width = pct + "%";

    if (trState.open) {
        document.getElementById("tr-main").textContent = "Running...";
        document.getElementById("tr-main").style.color = "var(--primary)";
        document.getElementById("tr-sub").textContent = trState.current + " / " + trState.total + " (" + trState.failed + " failed)";
    } else if (done) {
        if (trState.failed > 0) {
            document.getElementById("tr-main").textContent = "Failed";
            document.getElementById("tr-main").style.color = "var(--error)";
            document.getElementById("tr-bar").style.background = "var(--error)";
        } else {
            document.getElementById("tr-main").textContent = "Passed";
            document.getElementById("tr-main").style.color = "var(--success)";
            document.getElementById("tr-bar").style.background = "var(--success)";
        }
        document.getElementById("tr-sub").textContent = trState.passed + " passed, " + trState.failed + " failed.";
    }
}

// ==================== Page Navigation ====================
var pageTitles = {
    dashboard: "dashboard",
    http: "http",
    projects: "projects",
    settings: "settings",
    logs: "logs"
};

document.querySelectorAll(".ni").forEach(function (x) {
    x.addEventListener("click", function (e) {
        e.preventDefault();
        document.querySelectorAll(".ni").forEach(function (y) { y.classList.remove("on"); });
        x.classList.add("on");

        var page = x.getAttribute("data-page");
        document.querySelectorAll(".page").forEach(function (p) { p.classList.remove("active"); });
        var target = document.getElementById("page-" + page);
        if (target) target.classList.add("active");

        document.getElementById("page-title").textContent = t(page);
    });
});

// ==================== Theme Toggle ====================
function toggleTheme() { 
    var r = document.documentElement; 
    var isLight = r.classList.toggle("light"); 
    localStorage.setItem("dext-theme", isLight ? "light" : "dark"); 
    document.getElementById("theme-icon").textContent = isLight ? "light_mode" : "dark_mode"; 
    updateChartsTheme();
}
(function () { var t = localStorage.getItem("dext-theme"); if (t == "light") { document.documentElement.classList.add("light"); document.getElementById("theme-icon").textContent = "light_mode"; } })();

// ==================== HTTP Client Functions ====================
function httpNew() {
    document.getElementById("http-editor").value = "### New Request\nGET https://api.example.com/resource\nContent-Type: application/json\n\n";
    httpParse();
}

function httpUpload(event) {
    var file = event.target.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function (e) {
        document.getElementById("http-editor").value = e.target.result;
        httpParse();
    };
    reader.readAsText(file);
    event.target.value = ""; // Reset for re-upload
}

function httpDownload() {
    var content = document.getElementById("http-editor").value;
    var blob = new Blob([content], { type: "text/plain" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "requests.http";
    a.click();
}

function httpParse() {
    var content = document.getElementById("http-editor").value;
    // Parse using backend API
    fetch("/api/http/parse", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: content })
    })
        .then(function (r) { return r.json(); })
        .then(function (data) {
            httpParsedRequests = data.requests || [];
            httpParsedVars = data.variables || [];
            httpResults = {}; // Reset results on parse
            httpRenderChips();
            httpRenderVars();
        })
        .catch(function (err) {
            console.error("Parse error:", err);
            // Fallback: simple local parse
            httpLocalParse(content);
        });
}

function httpLocalParse(content) {
    // Fallback simple parser
    var lines = content.split("\n");
    var requests = [];
    var currentName = "";
    var methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.startsWith("###")) {
            currentName = line.substring(3).trim();
        } else {
            for (var j = 0; j < methods.length; j++) {
                if (line.startsWith(methods[j] + " ")) {
                    requests.push({
                        name: currentName || "Request " + (requests.length + 1),
                        method: methods[j],
                        url: line.substring(methods[j].length + 1).trim(),
                        lineNumber: i + 1
                    });
                    currentName = "";
                    break;
                }
            }
        }
    }
    httpParsedRequests = requests;
    httpRenderChips();
}

// HTTP Client State
var httpParsedRequests = [];
var httpParsedVars = [];
var httpSelectedIndex = 0;
var httpHistoryList = [];
var httpResults = {}; // Index -> Result Map

function httpRenderChips() {
    var container = document.getElementById("http-requests");
    if (httpParsedRequests.length === 0) {
        container.innerHTML = "<span style='color:var(--on-surface-v);font-size:11px'>No requests detected</span>";
        return;
    }
    var html = "";
    for (var i = 0; i < httpParsedRequests.length; i++) {
        var r = httpParsedRequests[i];
        var active = i === httpSelectedIndex ? " on" : "";
        var methodClass = r.method.toLowerCase();

        // Status dot if we have a result
        var dot = "";
        if (httpResults[i]) {
            var stClass = getStatusClass(httpResults[i].statusCode);
            dot = `<span class="http-dot ${stClass}"></span>`;
        }

        html += `<div class="http-chip${active}" onclick="httpSelectRequest(${i})">
                    ${dot}
                    <span class="method ${methodClass}">${r.method}</span>
                    ${r.name || "Unnamed"}
                 </div>`;
    }
    container.innerHTML = html;
}

function httpRenderVars() {
    var container = document.getElementById("http-vars-list");
    if (!httpParsedVars || httpParsedVars.length === 0) {
        container.innerHTML = "<span style='color:var(--outline);font-size:11px'>No variables defined</span>";
        return;
    }
    var html = "";
    for (var i = 0; i < httpParsedVars.length; i++) {
        var v = httpParsedVars[i];
        html += '<div class="http-var">';
        html += '<span class="http-var-name">@' + v.name + '</span>';
        html += '<span class="http-var-value">' + (v.value || v.envVarName || '') + '</span>';
        html += '</div>';
    }
    container.innerHTML = html;
}

function httpSelectRequest(index) {
    httpSelectedIndex = index;
    httpRenderChips();

    // Show previous result if exists
    if (httpResults[index]) {
        renderHttpResult(httpResults[index]);
    } else {
        // Clear UI
        document.getElementById("http-status").textContent = "--";
        document.getElementById("http-status").className = "http-status";
        document.getElementById("http-time").textContent = "--";
        document.getElementById("http-body").textContent = "";
        document.getElementById("http-headers").textContent = "";
    }
}

function httpTab(tab) {
    document.querySelectorAll(".http-tab").forEach(function (t) { t.classList.remove("on"); });
    document.querySelector('.http-tab[data-tab="' + tab + '"]').classList.add("on");
    document.getElementById("http-body").style.display = tab === "body" ? "block" : "none";
    document.getElementById("http-headers").style.display = tab === "headers" ? "block" : "none";
}

async function httpExecute() {
    if (httpParsedRequests.length === 0) {
        httpParse();
        await new Promise(function (r) { setTimeout(r, 300); });
    }

    if (httpParsedRequests.length === 0) {
        alert("No requests to execute. Check your .http syntax.");
        return;
    }

    var request = httpParsedRequests[httpSelectedIndex];
    document.getElementById("http-status").textContent = "Loading...";
    document.getElementById("http-status").className = "http-status";
    document.getElementById("http-time").textContent = "--";
    document.getElementById("http-body").textContent = "Executing request...";
    document.getElementById("http-headers").textContent = "";

    try {
        var response = await fetch("/api/http/execute", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                content: document.getElementById("http-editor").value,
                requestIndex: httpSelectedIndex
            })
        });
        var result = await response.json();

        // Save result
        httpResults[httpSelectedIndex] = result;
        renderHttpResult(result);
        httpRenderChips();

    } catch (err) {
        document.getElementById("http-status").textContent = "Error";
        document.getElementById("http-status").className = "http-status err";
        document.getElementById("http-body").textContent = err.message || "Request failed";
    }
}

function renderHttpResult(result) {
    // Update UI
    var statusClass = getStatusClass(result.statusCode);
    document.getElementById("http-status").textContent = result.statusCode + " " + result.statusText;
    document.getElementById("http-status").className = "http-status " + statusClass;
    document.getElementById("http-time").textContent = result.durationMs + "ms";

    // Format body
    var body = result.responseBody || "";
    try {
        var parsed = JSON.parse(body);
        body = JSON.stringify(parsed, null, 2);
        body = syntaxHighlight(body);
    } catch (e) { /* Not JSON */ }
    document.getElementById("http-body").innerHTML = body;

    // Headers
    var headers = "";
    if (result.responseHeaders) {
        for (var key in result.responseHeaders) {
            headers += key + ": " + result.responseHeaders[key] + "\n";
        }
    }
    document.getElementById("http-headers").textContent = headers || "No headers";
}

async function httpExecuteAll() {
    for (var i = 0; i < httpParsedRequests.length; i++) {
        httpSelectedIndex = i;
        httpRenderChips();
        await httpExecute();
    }
}

function getStatusClass(code) {
    if (code >= 200 && code < 300) return "s2";
    if (code >= 300 && code < 400) return "s3";
    if (code >= 400 && code < 500) return "s4";
    if (code >= 500) return "s5";
    return "err";
}

function syntaxHighlight(json) {
    json = json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return json.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
        var cls = 'json-number';
        if (/^"/.test(match)) {
            if (/:$/.test(match)) {
                cls = 'json-key';
            } else {
                cls = 'json-string';
            }
        } else if (/true|false/.test(match)) {
            cls = 'json-boolean';
        } else if (/null/.test(match)) {
            cls = 'json-null';
        }
        return '<span class="' + cls + '">' + match + '</span>';
    });
}

// Editor change listener
document.getElementById("http-editor").addEventListener("input", function () {
    clearTimeout(window.httpParseTimeout);
    window.httpParseTimeout = setTimeout(httpParse, 500);
});

function httpToggleHistory() {
    var p = document.getElementById("http-history");
    if (p.style.display == "none") {
        p.style.display = "block";
        httpLoadHistory();
    } else {
        p.style.display = "none";
    }
}

function httpLoadHistory() {
    fetch("/api/http/history")
        .then(function (r) { return r.json() })
        .then(function (d) {
            httpHistoryList = d;
            var c = document.getElementById("http-history-list");
            if (d.length == 0) { c.innerHTML = "<div style='padding:20px;color:#666'>No history</div>"; return; }
            var h = "";
            for (var i = 0; i < d.length; i++) {
                var item = d[i];
                var date = new Date(item.timestamp).toLocaleString();
                var stClass = getStatusClass(item.statusCode);
                h += `<div class="http-hist-item" onclick="httpRestoreHistory(${i})">
                        <div class="http-hist-top">
                            <span class="method ${item.method.toLowerCase()}">${item.method}</span>
                            <span class="url">${item.url}</span>
                        </div>
                        <div class="http-hist-bot">
                            <span class="status ${stClass}">${item.statusCode}</span>
                            <span class="time">${item.durationMs}ms</span>
                            <span class="date">${date}</span>
                        </div>
                      </div>`;
            }
            c.innerHTML = h;
        });
}

function httpRestoreHistory(idx) {
    if (httpHistoryList[idx]) {
        var item = httpHistoryList[idx];
        document.getElementById("http-editor").value = item.content;
        document.getElementById("http-history").style.display = "none";
        httpParse();
    }
}

// ==================== Test Tab Logic ====================
window.discoveredTests = {}; // Maps ProjectPath -> ProjectDetails
window.activeTestSessions = JSON.parse(localStorage.getItem("dext-test-sessions") || "{}");
var testSuite = {}; // Maps ProjectPath -> { Name, Fixtures -> { Name, Tests -> { Name, Status, Logs, Duration, ErrorMessage } } }
var currentTestDetail = null;
var testsActiveGroupBy = "hierarchy";
var testsSelectedPaths = new Set(); // Stores checked paths: "project|unit|fixture|method"

// Hook to automatically populate test projects dropdown when workspace is scanned
function updateTestProjectsDropdown(scanData) {
    var select = document.getElementById("tests-pj-select");
    if (!select) return;
    
    // Clear and add placeholder
    select.innerHTML = '<option value="">Select Test Project...</option>';
    
    if (scanData && scanData.tests) {
        scanData.tests.forEach(function(pj) {
            var opt = document.createElement("option");
            opt.value = pj.path;
            opt.textContent = pj.name;
            select.appendChild(opt);
        });
        
        // Auto discover all discovered test projects on first scan
        scanData.tests.forEach(function(pj) {
            discoverTestProject(pj.path);
        });
    }
}

// Discover tests in a specific project via AST
async function discoverTestProject(projectPath) {
    if (!projectPath) return;
    try {
        var r = await fetch("/api/tests/discover?project=" + encodeURIComponent(projectPath));
        if (r.ok) {
            var data = await r.json();
            window.discoveredTests[projectPath] = data;
            
            // Build/Merge into global testSuite
            var pjName = data.project || "Unknown Project";
            testSuite[projectPath] = {
                name: pjName,
                path: projectPath,
                fixtures: {}
            };
            
            if (data.fixtures) {
                data.fixtures.forEach(function(fix) {
                    var fName = fix.name;
                    testSuite[projectPath].fixtures[fName] = {
                        name: fName,
                        unit: fix.unit,
                        line: fix.line,
                        tests: {}
                    };
                    
                    if (fix.tests) {
                        fix.tests.forEach(function(t) {
                            var tName = t.name;
                            testSuite[projectPath].fixtures[fName].tests[tName] = {
                                name: tName,
                                line: t.line,
                                status: "none",
                                logs: "",
                                duration: null,
                                errorMessage: ""
                            };
                        });
                    }
                });
            }
            
            renderTestTree();
            updateSessionSelectorUI();
        }
    } catch(e) {
        console.error("Error discovering test project:", projectPath, e);
    }
}

function updateTestState(evt, data) {
    if (evt === 'run_start') {
        // Reset status for all tests in discovered suites
        for (var p in testSuite) {
            for (var f in testSuite[p].fixtures) {
                for (var t in testSuite[p].fixtures[f].tests) {
                    testSuite[p].fixtures[f].tests[t].status = "none";
                    testSuite[p].fixtures[f].tests[t].logs = "";
                    testSuite[p].fixtures[f].tests[t].duration = null;
                    testSuite[p].fixtures[f].tests[t].errorMessage = "";
                }
            }
        }
        trState = { total: data.total || data.totalTests || 0, current: 0, passed: 0, failed: 0, open: true };
        updateTestProgress();
        renderTestTree();
        return;
    }

    if (evt === 'run_complete') {
        trState.open = false;
        updateTestProgress(true);
        renderTestTree();
        return;
    }

    if (evt === 'test_start') {
        var fixName = data.fixture || "";
        var tName = data.test || "";
        for (var p in testSuite) {
            if (testSuite[p].fixtures[fixName] && testSuite[p].fixtures[fixName].tests[tName]) {
                testSuite[p].fixtures[fixName].tests[tName].status = "running";
                renderTestTree();
                break;
            }
        }
        return;
    }

    if (evt === 'test_complete') {
        var fixName = data.fixture || "";
        var tName = data.test || "";
        var status = data.status || "Passed";
        var dur = data.duration || 0;
        var err = data.errorMessage || data.exceptionmessage || "";
        var stack = data.stackTrace || data.status || ""; // TestInsight maps stack to status field

        trState.current++;
        if (status === "Passed") trState.passed++; else trState.failed++;
        updateTestProgress();

        for (var p in testSuite) {
            var pj = testSuite[p];
            if (pj.fixtures[fixName] && pj.fixtures[fixName].tests[tName]) {
                var test = pj.fixtures[fixName].tests[tName];
                test.status = status.toLowerCase();
                test.duration = dur;
                test.errorMessage = err;
                test.logs = (test.logs || "") + (err ? `Error: ${err}\n` : "") + (stack ? `Stack Trace:\n${stack}\n` : "") + `Duration: ${dur}ms\n`;
                
                renderTestTree();
                
                if (currentTestDetail && currentTestDetail.fixture === fixName && currentTestDetail.test === tName) {
                    showTestDetail(p, fixName, tName);
                }
                break;
            }
        }
    }
}

function testsChangeGroupBy(groupBy) {
    testsActiveGroupBy = groupBy;
    renderTestTree();
}

function renderTestTree() {
    var c = document.getElementById("test-tree");
    if (!c) return;

    var h = "";
    var totalTestsCount = 0;

    // Filter query
    var filterText = (document.getElementById("test-filter")?.value || "").toLowerCase();

    if (testsActiveGroupBy === "hierarchy") {
        // Group by: Project > Unit > Fixture > Method
        for (var p in testSuite) {
            var pj = testSuite[p];
            h += `<div class="test-tree-item test-project-node"><span class="ms material-symbols-outlined" style="margin-right:8px;font-size:18px">folder_zip</span>${pj.name}</div>`;
            
            for (var f in pj.fixtures) {
                var fix = pj.fixtures[f];
                if (filterText && !f.toLowerCase().includes(filterText) && !fix.unit.toLowerCase().includes(filterText)) continue;
                
                h += `<div class="test-tree-item test-fixture-node"><span class="ms material-symbols-outlined" style="margin-right:8px;font-size:18px">folder</span>${fix.unit}.${f}</div>`;
                
                for (var t in fix.tests) {
                    var test = fix.tests[t];
                    if (filterText && !t.toLowerCase().includes(filterText)) continue;
                    totalTestsCount++;
                    
                    var path = `${p}|${fix.unit}|${f}|${t}`;
                    var checked = testsSelectedPaths.has(path) ? "checked" : "";
                    
                    var icon = "radio_button_unchecked";
                    var stClass = "st-none";
                    var badge = "";
                    
                    if (test.status === "passed") { icon = "check_circle"; stClass = "st-pass"; badge = '<span class="test-status-badge pass">Pass</span>'; }
                    else if (test.status === "failed") { icon = "cancel"; stClass = "st-fail"; badge = '<span class="test-status-badge fail">Fail</span>'; }
                    else if (test.status === "skipped") { icon = "remove_circle"; stClass = "st-skip"; badge = '<span class="test-status-badge skip">Skip</span>'; }
                    else if (test.status === "running") { icon = "hourglass_empty"; stClass = "st-none"; badge = '<span class="test-status-badge run">Running</span>'; }
                    
                    var selected = (currentTestDetail && currentTestDetail.fixture === f && currentTestDetail.test === t) ? "selected" : "";
                    
                    h += `<div class="test-tree-item test-method-node ${selected}" onclick="handleTestNodeClick(event, '${p}', '${f}', '${t}')">
                            <input type="checkbox" class="test-tree-checkbox" ${checked} onchange="toggleTestSelection('${path}', this.checked)">
                            <i class="test-status-icon ${stClass}">${icon}</i>
                            <span style="flex:1">${t}</span>
                            ${badge}
                          </div>`;
                }
            }
        }
    } else if (testsActiveGroupBy === "outcome") {
        // Group by: Passed, Failed, Skipped, Not Run
        var groups = { passed: [], failed: [], skipped: [], none: [], running: [] };
        for (var p in testSuite) {
            for (var f in testSuite[p].fixtures) {
                for (var t in testSuite[p].fixtures[f].tests) {
                    var test = testSuite[p].fixtures[f].tests[t];
                    test.projPath = p;
                    test.fixture = f;
                    groups[test.status].push(test);
                }
            }
        }
        
        var renderOutcomeGroup = function(title, list, icon, color) {
            if (list.length === 0) return "";
            var res = `<div class="test-tree-item test-project-node" style="color:${color}"><span class="ms material-symbols-outlined" style="margin-right:8px;font-size:18px">${icon}</span>${title} (${list.length})</div>`;
            list.forEach(function(test) {
                totalTestsCount++;
                var path = `${test.projPath}|${testSuite[test.projPath].fixtures[test.fixture].unit}|${test.fixture}|${test.name}`;
                var checked = testsSelectedPaths.has(path) ? "checked" : "";
                var selected = (currentTestDetail && currentTestDetail.fixture === test.fixture && currentTestDetail.test === test.name) ? "selected" : "";
                res += `<div class="test-tree-item test-method-node ${selected}" style="padding-left:24px" onclick="handleTestNodeClick(event, '${test.projPath}', '${test.fixture}', '${test.name}')">
                            <input type="checkbox" class="test-tree-checkbox" ${checked} onchange="toggleTestSelection('${path}', this.checked)">
                            <span style="flex:1">${test.fixture}.${test.name}</span>
                        </div>`;
            });
            return res;
        };
        
        h += renderOutcomeGroup("Failed", groups.failed, "cancel", "#e74c3c");
        h += renderOutcomeGroup("Running", groups.running, "hourglass_empty", "var(--primary)");
        h += renderOutcomeGroup("Passed", groups.passed, "check_circle", "#2ecc71");
        h += renderOutcomeGroup("Skipped", groups.skipped, "remove_circle", "#f1c40f");
        h += renderOutcomeGroup("Not Run", groups.none, "radio_button_unchecked", "var(--on-surface-v)");
    } else {
        // Fallback simple view
        h += `<div style="padding:20px;color:var(--on-surface-v);text-align:center">Grouping mode "${testsActiveGroupBy}" populated in background. Select Hierarchy or Outcome.</div>`;
    }

    if (totalTestsCount === 0 && Object.keys(testSuite).length === 0) {
        c.innerHTML = `<div style="padding:20px;color:var(--on-surface-v);text-align:center">
                            <span data-i18n="no_tests">No tests discovered.</span><br>
                            <span style="font-size:11px">Make sure you have test projects (*.dpr / *.dproj) in your active workspace.</span>
                        </div>`;
        return;
    }

    c.innerHTML = h;

    // Update Summaries
    var tot = document.getElementById("tests-total");
    if (tot) tot.textContent = totalTestsCount + " Tests";
    var pass = document.getElementById("tests-passed");
    if (pass) pass.textContent = trState.passed + " Pass";
    var fail = document.getElementById("tests-failed");
    if (fail) fail.textContent = trState.failed + " Fail";
}

function toggleTestSelection(path, checked) {
    if (checked) testsSelectedPaths.add(path);
    else testsSelectedPaths.delete(path);
}

function handleTestNodeClick(event, projPath, fixture, test) {
    if (event.target.classList.contains("test-tree-checkbox")) return;
    showTestDetail(projPath, fixture, test);
}

function testDetailTab(tab) {
    document.querySelectorAll("#test-detail-tabs .http-tab").forEach(function(t) { t.classList.remove("on"); });
    document.querySelector(`#test-detail-tabs .http-tab[data-tab="${tab}"]`).classList.add("on");
    document.querySelectorAll(".test-tab-content").forEach(function(c) { c.style.display = "none"; });
    document.getElementById(`tab-${tab}`).style.display = "block";
}

function showTestDetail(projPath, fixtureName, testName) {
    currentTestDetail = { projPath: projPath, fixture: fixtureName, test: testName };
    var pj = testSuite[projPath];
    if (!pj) return;
    var fix = pj.fixtures[fixtureName];
    if (!fix) return;
    var test = fix.tests[testName];
    if (!test) return;

    document.getElementById("test-detail-tabs").style.display = "flex";
    document.getElementById("test-detail-title").textContent = `${pj.name} > ${fix.unit}.${fixtureName} > ${testName}`;
    document.getElementById("test-detail-duration").textContent = test.duration ? test.duration + "ms" : "--";
    
    // Core Test Logs
    document.getElementById("test-detail-logs").textContent = test.logs || "No logs captured during execution.";

    // S26 Assertion Diff Panel
    var diffTabBtn = document.getElementById("btn-test-diff");
    if (test.status === "failed" && test.errorMessage) {
        var msg = test.errorMessage;
        // Standard Delphi/DUnitX equality parse: "Expected: <banana> actual: <maçã>"
        var expectedMatch = msg.match(/Expected:\s*<(.*?)>/i);
        var actualMatch = msg.match(/actual:\s*<(.*?)>/i);
        
        // Alternative standard assert format: "expected: 'banana' but was: 'maçã'"
        if (!expectedMatch) {
            expectedMatch = msg.match(/expected:\s*'(.*?)'/i);
            actualMatch = msg.match(/but was:\s*'(.*?)'/i);
        }

        if (expectedMatch && actualMatch) {
            diffTabBtn.style.display = "inline-block";
            document.getElementById("diff-expected").textContent = expectedMatch[1];
            document.getElementById("diff-actual").textContent = actualMatch[1];
        } else {
            // General string fallback if no clear match but failed
            diffTabBtn.style.display = "inline-block";
            document.getElementById("diff-expected").textContent = "Trigger Failure Details:\n" + msg;
            document.getElementById("diff-actual").textContent = "N/A";
        }
    } else {
        diffTabBtn.style.display = "none";
        testDetailTab("test-logs"); // Fallback to logs
    }

    // --- S24 Test-to-Log Link Correlation (The Obsidian Link) ---
    if (window.logStore && window.logStore.length > 0) {
        // Filter global logStore for logs generated during this test execution
        // Since we don't have SpanId matching everywhere yet, we search for logs containing test name or fixture name
        var filteredLogs = window.logStore.filter(function(log) {
            var text = (log.message || "").toLowerCase();
            return text.includes(testName.toLowerCase()) || text.includes(fixtureName.toLowerCase());
        });

        if (filteredLogs.length > 0) {
            var logText = "--- TELEMETRY TEST-TO-LOG LINK (CORRELATED LOGS) ---\n";
            filteredLogs.forEach(function(l) {
                logText += `[${l.timestamp.split('T')[1].substring(0,8)}] [${l.level}] ${l.message}\n`;
            });
            document.getElementById("test-detail-logs").textContent += "\n\n" + logText;
        }
    }

    // --- Delphi Code Coverage Premium Integration ---
    var covTabBtn = document.getElementById("btn-test-coverage");
    var unitName = (fix.unit || "").toLowerCase();
    
    if (window.coverageUnitsMap && window.coverageUnitsMap[unitName]) {
        var covInfo = window.coverageUnitsMap[unitName];
        covTabBtn.style.display = "inline-block";
        
        // Update stats header inside coverage panel
        document.getElementById("coverage-percentage-label").textContent = covInfo.percent.toFixed(1) + "%";
        document.getElementById("coverage-percentage-fill").style.width = covInfo.percent + "%";
        
        // Fetch original unit file via the workspace or direct /api/fs/read
        // We look for a file named "UnitName.pas" in activeWorkspace or projects assets
        var possiblePasPath = "";
        if (activeWorkspace) {
            possiblePasPath = activeWorkspace + "\\" + fix.unit + ".pas";
        }

        // Set loader/status first
        var codePre = document.getElementById("coverage-source-code");
        codePre.innerHTML = "Loading source file for highlighting...";
        
        // Fetch source content asynchronously
        var loadSource = async function() {
            try {
                // If possiblePasPath isn't perfect, we can also search for files, or let the user choose, but /api/fs/read with workspace fallback works great
                var r = await fetch("/api/fs/read?path=" + encodeURIComponent(possiblePasPath));
                if (!r.ok && activeWorkspace) {
                    // Try recursive or absolute search in workspace if simple path fails
                    // Dext usually scans directories. We can look up in lastWorkspaceScan if needed, but simple read is standard first step
                }
                
                if (r.ok) {
                    var srcText = await r.text();
                    var lines = srcText.split(/\r?\n/);
                    var outputHtml = "";
                    
                    // Create lines map for quick O(1) lookup
                    var linesMap = {};
                    covInfo.lines.forEach(function(l) {
                        linesMap[l.number] = l.covered;
                    });
                    
                    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
                        var lineNum = lineIdx + 1;
                        var rawText = lines[lineIdx];
                        // Simple escaping to prevent HTML breaking code display
                        var escText = rawText.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                        
                        var lineStyle = "";
                        var badgeHtml = "";
                        if (linesMap[lineNum] !== undefined) {
                            var isCovered = linesMap[lineNum];
                            lineStyle = isCovered ? "background-color: rgba(46, 204, 113, 0.15); border-left: 3px solid #2ecc71;" : "background-color: rgba(231, 76, 60, 0.15); border-left: 3px solid #e74c3c;";
                            badgeHtml = `<span style="font-size: 8px; font-weight: bold; margin-left: 8px; opacity: 0.7; color: ${isCovered ? '#2ecc71' : '#e74c3c'};">${isCovered ? 'COVERED' : 'UNCOVERED'}</span>`;
                        }
                        
                        outputHtml += `<div style="display: flex; align-items: center; min-height: 20px; padding: 1px 6px; ${lineStyle}">` +
                                      `<span style="width: 45px; text-align: right; margin-right: 15px; color: var(--on-surface-v); user-select: none; font-size: 11px;">${lineNum}</span>` +
                                      `<pre style="margin: 0; font-family: monospace; font-size: 12px; white-space: pre;">${escText}</pre>` +
                                      badgeHtml +
                                      `</div>`;
                    }
                    codePre.innerHTML = outputHtml;
                } else {
                    codePre.innerHTML = `<span style="color: var(--error)">Could not locate unit source file at:<br>${possiblePasPath}</span>`;
                }
            } catch(ex) {
                codePre.innerHTML = `<span style="color: var(--error)">Failed to load unit source: ${ex.message}</span>`;
            }
        };
        loadSource();
    } else {
        covTabBtn.style.display = "none";
    }

    renderTestTree();
}


async function testsRunAll() {
    var projectsToRun = Object.keys(testSuite);
    if (projectsToRun.length === 0) {
        alert("No test projects discovered. Please select a workspace with tests first.");
        return;
    }
    
    // Clear selections and select all
    testsSelectedPaths.clear();
    for (var p in testSuite) {
        for (var f in testSuite[p].fixtures) {
            for (var t in testSuite[p].fixtures[f].tests) {
                testsSelectedPaths.add(`${p}|${testSuite[p].fixtures[f].unit}|${f}|${t}`);
            }
        }
    }

    testsRunSelected();
}

async function testsRunSelected(runCoverage) {
    if (testsSelectedPaths.size === 0) {
        alert("Please select at whom to run tests using checkboxes first.");
        return;
    }

    var projects = new Set();
    var tests = [];
    
    testsSelectedPaths.forEach(function(path) {
        var parts = path.split("|"); // projPath|unit|fixture|test
        projects.add(parts[0]);
        tests.push(`${parts[1]}.${parts[2]}.${parts[3]}`); // Format: Unit.Fixture.Method
    });

    var tree = document.getElementById("test-tree");
    var modeText = runCoverage ? "with Cobertura" : "in Parallel Workers";
    tree.innerHTML = `<div style="padding:20px"><span class="loader"></span> Executing Selected Tests ${modeText}...<br><span style="font-size:11px;color:var(--on-surface-v)">Check Live Logs or SSE Stream below for real-time trace outputs.</span></div>`;

    try {
        var r = await fetch("/api/tests/run", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                projects: Array.from(projects),
                tests: tests,
                coverage: !!runCoverage
            })
        });

        if (!r.ok) {
            tree.innerHTML = `<div style="padding:20px;color:var(--error)">Execution failed: ${await r.text()}</div>`;
        } else {
            var runResult = await r.json();
            // Surface any per-project errors (e.g. executable not found)
            var errors = [];
            if (runResult.results) {
                runResult.results.forEach(function(res) {
                    if (res.error) errors.push(res.error);
                });
            }
            if (errors.length > 0) {
                tree.innerHTML = `<div style="padding:20px;color:var(--error)"><b>Runner errors:</b><ul>${errors.map(e => `<li>${e}</li>`).join('')}</ul><span style="font-size:11px;color:var(--on-surface-v)">Make sure you built the test project(s) before running.</span></div>`;
            } else if (runCoverage) {
                // Fetch coverage detail shortly after run completes
                setTimeout(fetchAndRenderCoverageDetails, 3000);
            }
            // On success the test results will arrive via SSE events (run_start / test_complete / run_complete)
        }
    } catch(e) {
        tree.innerHTML = `<div style="padding:20px;color:var(--error)">Execution error: ${e.message}</div>`;
    }
}

async function fetchAndRenderCoverageDetails() {
    try {
        var r = await fetch("/api/tests/coverage-detail");
        if (r.ok) {
            var data = await r.json();
            if (data.available && data.xml) {
                window.coverageXmlData = data.xml;
                // Parse XML manually using DOMParser
                var parser = new DOMParser();
                var xmlDoc = parser.parseFromString(data.xml, "text/xml");
                var units = xmlDoc.getElementsByTagName("sourcefile");
                
                window.coverageUnitsMap = {};
                for (var i = 0; i < units.length; i++) {
                    var unit = units[i];
                    var name = unit.getAttribute("name") || "";
                    var pct = parseFloat(unit.getAttribute("percent") || "0");
                    
                    var linesList = [];
                    var lines = unit.getElementsByTagName("line");
                    for (var j = 0; j < lines.length; j++) {
                        var line = lines[j];
                        linesList.push({
                            number: parseInt(line.getAttribute("number")),
                            covered: line.getAttribute("covered") === "true"
                        });
                    }
                    window.coverageUnitsMap[name.toLowerCase()] = { percent: pct, lines: linesList };
                }
                
                console.log("Premium Coverage data parsed successfully!", window.coverageUnitsMap);
            }
        }
    } catch(e) {
        console.error("Error fetching detailed coverage summary:", e);
    }
}

// User-defined custom test sessions
function testsSaveSession() {
    var name = prompt("Enter a name for this custom Test Session:");
    if (!name) return;
    
    window.activeTestSessions[name] = Array.from(testsSelectedPaths);
    localStorage.setItem("dext-test-sessions", JSON.stringify(window.activeTestSessions));
    updateSessionSelectorUI();
    alert(`Test Session "${name}" saved successfully!`);
}

function testsLoadSession(name) {
    if (!name || !window.activeTestSessions[name]) return;
    
    testsSelectedPaths = new Set(window.activeTestSessions[name]);
    renderTestTree();
}

function updateSessionSelectorUI() {
    var select = document.getElementById("tests-session-select");
    if (!select) return;
    
    var keys = Object.keys(window.activeTestSessions);
    if (keys.length === 0) {
        select.style.display = "none";
        return;
    }
    
    select.style.display = "inline-block";
    select.innerHTML = '<option value="">-- Custom Sessions --</option>';
    keys.forEach(function(k) {
        var opt = document.createElement("option");
        opt.value = k;
        opt.textContent = k;
        select.appendChild(opt);
    });
}

function testsRunFailed() {
    alert("Not implemented");
}

function testsFilter() {
    var txt = document.getElementById("test-filter").value.toLowerCase();
    var items = document.querySelectorAll(".test-tree-item");
    for (var i = 0; i < items.length; i++) {
        var t = items[i].textContent.toLowerCase();
        items[i].style.display = t.indexOf(txt) >= 0 ? "flex" : "none";
    }
}

// ==================== Projects / Workspace Logic ====================
// ==================== Projects / Workspace Logic ====================
var activeWorkspace = "";
var feCurrentPath = "C:\\";

// Persist active workspace
if (localStorage.getItem("activeWorkspace")) {
    activeWorkspace = localStorage.getItem("activeWorkspace");
    updateWorkspaceUI(activeWorkspace);
    refreshWorkspace();
}

function openWorkspaceModal() {
    var el = document.getElementById("wk-modal");
    el.style.display = "flex"; // flex for centering
    loadFolder(activeWorkspace || "C:\\");
}

function closeWorkspaceModal() {
    document.getElementById("wk-modal").style.display = "none";
}

async function loadFolder(path) {
    try {
        if (!path) path = "C:\\";
        path = path.replace(/\\\\/g, "\\");
        if (path.endsWith("\\") && path.length > 3) path = path.substring(0, path.length - 1);

        // Handle Drive Letter Only (e.g. "C")
        if (path.length === 1 && path.match(/[a-z]/i)) path = path + ":\\";

        feCurrentPath = path;
        document.getElementById("fe-path").value = path;

        var list = [];
        try {
            var r = await fetch("/api/fs/list?path=" + encodeURIComponent(path));
            if (r.ok) list = await r.json();
            else list = [{ name: "Error loading folder", type: "file" }];
        } catch (e) {
            // Mock Fallback
            if (path == "C:\\") list = [{ name: "dev", type: "dir" }, { name: "Users", type: "dir" }];
            else if (path == "C:\\dev") list = [{ name: "Dext", type: "dir" }];
            else list = [{ name: "MockProject.dproj", type: "file" }];
        }

        var h = "";
        // Back item if not root
        if (path.length > 3) {
            h += `<div class="fe-item" onclick="navUp()"><i class="material-symbols-outlined" style="margin-right:10px;color:var(--primary)">arrow_back</i>..</div>`;
        }

        for (var i = 0; i < list.length; i++) {
            var it = list[i];
            var icon = it.type == "dir" ? "folder" : "description";
            var iconColor = it.type == "dir" ? "var(--primary)" : "var(--on-surface-v)";
            var nextPath = path.endsWith("\\") ? path + it.name : path + "\\" + it.name;
            // Escape backslashes for JS string
            var jsPath = nextPath.replace(/\\/g, "\\\\");

            var action = it.type == "dir" ? `onclick="loadFolder('${jsPath}')"` : "";

            h += `<div class="fe-item" ${action}>
                    <i class="material-symbols-outlined" style="margin-right:10px;color:${iconColor}">${icon}</i>${it.name}
                  </div>`;
        }
        document.getElementById("fe-list").innerHTML = h;
    } catch (e) { console.error(e); }
}

function navUp() {
    if (feCurrentPath.length <= 3) return; // At root
    var p = feCurrentPath.lastIndexOf("\\");
    if (p <= 2) loadFolder("C:\\");
    else loadFolder(feCurrentPath.substring(0, p));
}

function selectCurrentFolder() {
    updateWorkspaceUI(feCurrentPath);
    closeWorkspaceModal();
    refreshWorkspace();
}

function updateWorkspaceUI(path) {
    activeWorkspace = path;
    localStorage.setItem("activeWorkspace", activeWorkspace);

    // Header
    var headerEl = document.getElementById("header-wk-path");
    if (headerEl) {
        headerEl.textContent = path;
        headerEl.title = path;
    }

    // Card (if exists on page)
    var cardEl = document.getElementById("wk-path-card");
    if (cardEl) cardEl.textContent = path;
}

// Drag and Drop (Simple Paste of Path)
var modalContent = document.querySelector(".modal-content");
if (modalContent) {
    var overlay = document.getElementById("fe-drag-overlay");

    document.addEventListener("dragover", function (e) {
        e.preventDefault();
        if (document.getElementById("wk-modal").style.display === "flex") {
            overlay.style.display = "flex";
        }
    });

    overlay.addEventListener("dragleave", function (e) {
        overlay.style.display = "none";
    });

    overlay.addEventListener("drop", function (e) {
        e.preventDefault();
        overlay.style.display = "none";

        // Try to get file/folder
        if (e.dataTransfer.items) {
            // We can't get full path due to security, BUT
            // if user drags multiple items or files, we might just use the Name to filter?
            // Actually, standard drag drop is useless for Full Path.
            // However, if we support pasting TEXT (which some OS do when dragging folder to text editor),
            // we can check dataTransfer.getData("text").
            var text = e.dataTransfer.getData("text/plain");
            if (text && text.indexOf("\\") > 0) {
                loadFolder(text.trim());
            } else {
                // Fallback: Show message
                alert("Browser security prevents reading the full path of dropped folders.\nPlease paste the path into the input box manually.");
            }
        }
    });
}

async function refreshWorkspace() {
    if (!activeWorkspace) return;

    // Reset indicators
    var ids = ["scan-dproj", "scan-tests", "scan-http", "scan-docs"];
    ids.forEach(id => document.getElementById(id).innerHTML = '<span class="st-w">Scanning...</span>');

    try {
        var r = await fetch("/api/workspace/scan?path=" + encodeURIComponent(activeWorkspace));
        var res = await r.json();
        window.lastWorkspaceScan = res; // Save for fallback use

        // Render Results
        renderScanList("scan-dproj", res.projects, "folder");
        renderScanList("scan-tests", res.tests, "science");
        renderScanList("scan-http", res.httpFiles, "http");
        renderScanList("scan-docs", res.docs, "description");

        // Populate Dropdowns
        populateSelect("header-pj-select", res.projects, "activeProject");
        // NOTE: tests-pj-select is handled exclusively by updateTestProjectsDropdown
        populateSelect("http-file-select", res.httpFiles, "activeHttpFile");

        // Clear stale test suite before rediscovery, then populate test dropdown & discover all
        testSuite = {};
        updateTestProjectsDropdown(res);

    } catch (e) {
        ids.forEach(id => document.getElementById(id).innerHTML = '<span class="st-fail">Error scanning</span>');
    }
}

function populateSelect(id, items, storageKey) {
    var sel = document.getElementById(id);
    if (!sel) return;
    var current = sel.value;
    var saved = localStorage.getItem(storageKey);

    var h = `<option value="">Select...</option>`;
    if (items) {
        items.forEach(it => {
            var name = (typeof it === 'string') ? it : (it.name || "Unknown");
            var path = (typeof it === 'string') ? name : (it.path || name);
            // If it's just name and we are in workspace, maybe it's relative?
            // Usually res.projects are just names. res.tests are objects with paths.
            // res.httpFiles are just names (filenames in root/subdirs?) 
            // Actually Dext sidecar scan usually returns relative paths or full paths.
            h += `<option value="${path}">${name}</option>`;
        });
    }
    sel.innerHTML = h;

    // Restore selection
    if (saved) {
        // Find if saved exists in items
        var exists = items && items.some(it => {
            var val = (typeof it === 'string') ? it : (it.path || it.name);
            return val === saved;
        });
        if (exists) {
            sel.value = saved;
            // Trigger change logic if needed
            if (id === "tests-pj-select") discoverTestProject(saved);
            else if (id === "http-file-select") httpLoadFile(saved);
        } else if (items && items.length > 0) {
            // Select first by default if nothing saved
            var first = items[0];
            var firstVal = (typeof first === 'string') ? first : (first.path || first.name);
            sel.value = firstVal;
            if (id === "tests-pj-select") discoverTestProject(firstVal);
            else if (id === "http-file-select") httpLoadFile(firstVal);
        }
    } else if (items && items.length > 0) {
        var first = items[0];
        var firstVal = (typeof first === 'string') ? first : (first.path || first.name);
        sel.value = firstVal;
        if (id === "tests-pj-select") discoverTestProject(firstVal);
        else if (id === "http-file-select") httpLoadFile(firstVal);
    }
}

function selectActiveProject(path, skipSave) {
    if (!skipSave) localStorage.setItem("activeProject", path);
    var sel = document.getElementById("header-pj-select");
    if (sel) sel.value = path;
}

async function httpLoadFile(filename) {
    if (!filename) return;
    localStorage.setItem("activeHttpFile", filename);

    // Check if filename is path or just name
    var path = filename;
    if (activeWorkspace && !path.includes(":\\") && !path.startsWith("/")) {
        path = activeWorkspace + "\\" + filename;
    }

    try {
        var r = await fetch("/api/fs/read?path=" + encodeURIComponent(path));
        if (r.ok) {
            var text = await r.text();
            document.getElementById("http-editor").value = text;
            httpParse();
        }
    } catch (e) { console.error("Error loading http file:", e); }
}


function renderScanList(elId, items, icon) {
    var el = document.getElementById(elId);
    if (!items || items.length == 0) { el.innerHTML = '<span class="st-none">None found</span>'; return; }

    var h = "";
    var limit = 8;
    for (var i = 0; i < Math.min(items.length, limit); i++) {
        var it = items[i];
        var name = (typeof it === 'string') ? it : (it.name || "Unknown");
        var path = (typeof it === 'string') ? "" : (it.path || "");
        var action = "";

        // If it's a test project, allowing clicking to load details
        if (elId === 'scan-tests' && path) {
            // Escape backslashes and quotes for safe inclusion in onclick handler
            var safePath = path.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
            action = `style="cursor:pointer;color:var(--primary)" onclick="discoverTestProject('${safePath}')" title="${path}"`;
        }

        h += `<div class="pj-i" ${action}>
                <span class="ms material-symbols-outlined" style="font-size:16px;margin-right:5px">${icon}</span>${name}
              </div>`;
    }
    if (items.length > limit) h += `<div class="pj-i" style="font-style:italic">+${items.length - limit} more...</div>`;
    el.innerHTML = h;
}

// Legacy test functions replaced by S26 Premium Explorer Logic in Test Tab Logic

// ==================== Distributed Tracing (S24) ====================
var traceStore = {}; // trace_id -> { spans: [], root: null }
var activeTraceId = null;
var logStore = [];
var activeLogAppFilter = "";
var activeLogSearchFilter = "";
var activeTraceAppFilter = "";

// Debounce timers: prevent DOM thrashing when many spans arrive rapidly
var renderTraceDebounce = null;
var renderLogsDebounce = null;
var RENDER_DEBOUNCE_MS = 250;

function scheduleRenderTraces() {
    clearTimeout(renderTraceDebounce);
    renderTraceDebounce = setTimeout(function() {
        updateAppFilters();
        renderTraceList();
    }, RENDER_DEBOUNCE_MS);
}

function scheduleRenderLogs() {
    clearTimeout(renderLogsDebounce);
    renderLogsDebounce = setTimeout(function() {
        updateAppFilters();
        renderLogs();
    }, RENDER_DEBOUNCE_MS);
}

function processTrace(log) {
    var tid = log.trace_id;
    var isNew = false;
    if (!traceStore[tid]) {
        traceStore[tid] = { spans: [], startTime: log.ts, name: log.msg || "Trace " + tid.substring(0,8) };
        isNew = true;
    }
    
    // Add span to trace
    traceStore[tid].spans.push(log);
    
    if (!loadingHistory) {
        // Limit traceStore to 500 unique traces (only during live streaming, not bulk history)
        var traceKeys = Object.keys(traceStore);
        if (traceKeys.length > 500) {
            var oldest = traceKeys.sort(function(a,b) {
                return new Date(traceStore[a].startTime) - new Date(traceStore[b].startTime);
            })[0];
            if (oldest !== activeTraceId) delete traceStore[oldest];
        }
        
        // Schedule deferred render (debounced to avoid DOM thrashing)
        scheduleRenderTraces();
        
        // Auto-select if first trace or already active
        if (!activeTraceId && isNew) {
            setTimeout(function() { if (!activeTraceId) selectTrace(tid); }, RENDER_DEBOUNCE_MS + 50);
        } else if (activeTraceId === tid) {
            clearTimeout(window._traceDetailDebounce);
            window._traceDetailDebounce = setTimeout(function() { renderTraceDetail(tid); }, RENDER_DEBOUNCE_MS);
        }
    }
}

function renderTraceList() {
    var el = document.getElementById("trace-list");
    if (!el) return;
    
    var filterText = document.getElementById("trace-filter").value.toLowerCase();
    
    var h = "";
    var sortedIds = Object.keys(traceStore).sort((a,b) => new Date(traceStore[b].startTime) - new Date(traceStore[a].startTime));
    
    sortedIds.forEach(tid => {
        var t = traceStore[tid];
        var active = tid === activeTraceId ? "active" : "";
        var time = new Date(t.startTime).toLocaleTimeString();
        var status = t.spans.some(s => s.lvl === "Error") ? "error" : "success";
        
        // App filtering
        var appName = t.spans[0] ? (t.spans[0].app || "App") : "App";
        if (activeTraceAppFilter && appName !== activeTraceAppFilter) return;

        // Search text filtering
        if (filterText && t.name.toLowerCase().indexOf(filterText) < 0 && tid.toLowerCase().indexOf(filterText) < 0) return;
        
        h += `<div class="trace-item ${active}" onclick="selectTrace('${tid}')">
                <div class="trace-item-top">
                    <span class="trace-item-name">${t.name}</span>
                    <span class="trace-item-time">${time}</span>
                </div>
                <div class="trace-item-meta">
                    <span><span class="trace-status ${status}"></span>${t.spans.length} Spans</span>
                    <span style="font-size: 10px; font-weight: 600; padding: 1px 6px; border-radius: 4px; background: var(--outline-v); color: var(--on-surface-v); margin-left: 6px;">${appName}</span>
                    <span style="color:var(--outline)">${tid.substring(0,8)}...</span>
                </div>
              </div>`;
    });
    el.innerHTML = h;
}

function selectTrace(tid) {
    activeTraceId = tid;
    renderTraceList();
    renderTraceDetail(tid);
}

function tracesFilter() {
    renderTraceList();
}

function tracesFilterByApp(app) {
    activeTraceAppFilter = app;
    renderTraceList();
}

function logsFilterByApp(app) {
    activeLogAppFilter = app;
    renderLogs();
}

function logsFilter() {
    activeLogSearchFilter = document.getElementById("log-filter").value.toLowerCase();
    renderLogs();
}

function logsClear() {
    logStore = [];
    renderLogs();
    updateAppFilters();
}

function renderLogs() {
    var logs1 = document.getElementById("logs");
    var logs2 = document.getElementById("logs-full");
    if (!logs1 && !logs2) return;

    var html1 = "";
    var html2 = "";

    var filtered = logStore.filter(function(item) {
        var matchesApp = !activeLogAppFilter || item.app === activeLogAppFilter;
        var matchesSearch = !activeLogSearchFilter || item.message.toLowerCase().indexOf(activeLogSearchFilter) >= 0;
        return matchesApp && matchesSearch;
    });

    // Render logs1 (last 100)
    var list1 = filtered.slice(-100);
    list1.forEach(function(item) {
        var t = new Date(item.timestamp).toLocaleTimeString();
        var x = item.level.toLowerCase().indexOf("error") >= 0 ? "log-e" : item.level.toLowerCase().indexOf("warn") >= 0 ? "log-w" : "log-i";
        html1 += "<div class=\"log\"><span class=\"log-t\">[" + t + "]</span> <span style=\"font-size: 10px; font-weight: 600; padding: 1px 6px; border-radius: 4px; background: var(--outline-v); color: var(--on-surface-v); margin-right: 6px;\">" + item.app + "</span><span class=\"" + x + "\">" + item.message + "</span></div>";
    });

    // Render logs2 (last 500)
    var list2 = filtered.slice(-500);
    list2.forEach(function(item) {
        var t = new Date(item.timestamp).toLocaleTimeString();
        var x = item.level.toLowerCase().indexOf("error") >= 0 ? "log-e" : item.level.toLowerCase().indexOf("warn") >= 0 ? "log-w" : "log-i";
        html2 += "<div class=\"log\"><span class=\"log-t\">[" + t + "]</span> <span style=\"font-size: 10px; font-weight: 600; padding: 1px 6px; border-radius: 4px; background: var(--outline-v); color: var(--on-surface-v); margin-right: 6px;\">" + item.app + "</span><span class=\"" + x + "\">" + item.message + "</span></div>";
    });

    if (logs1) {
        logs1.innerHTML = html1 || '<div class="log"><span class="log-t">[--:--:--]</span> No logs matching filters.</div>';
        logs1.scrollTop = logs1.scrollHeight;
    }
    if (logs2) {
        logs2.innerHTML = html2 || '<div class="log"><span class="log-t">[--:--:--]</span> No logs matching filters.</div>';
        logs2.scrollTop = logs2.scrollHeight;
    }
}

function updateAppFilters() {
    var uniqueApps = new Set();
    
    // Extract apps from logStore
    logStore.forEach(function(item) {
        if (item.app) uniqueApps.add(item.app);
    });

    // Extract apps from traceStore
    Object.keys(traceStore).forEach(function(tid) {
        var t = traceStore[tid];
        if (t.spans && t.spans[0] && t.spans[0].app) {
            uniqueApps.add(t.spans[0].app);
        }
    });

    // Update log-app-filter dropdown
    var logSelect = document.getElementById("log-app-filter");
    if (logSelect) {
        var currentLogVal = logSelect.value;
        var logHtml = '<option value="">All Applications</option>';
        uniqueApps.forEach(function(app) {
            logHtml += '<option value="' + app + '">' + app + '</option>';
        });
        logSelect.innerHTML = logHtml;
        logSelect.value = currentLogVal;
    }

    // Update trace-app-filter dropdown
    var traceSelect = document.getElementById("trace-app-filter");
    if (traceSelect) {
        var currentTraceVal = traceSelect.value;
        var traceHtml = '<option value="">All Applications</option>';
        uniqueApps.forEach(function(app) {
            traceHtml += '<option value="' + app + '">' + app + '</option>';
        });
        traceSelect.innerHTML = traceHtml;
        traceSelect.value = currentTraceVal;
    }
}

function renderTraceDetail(tid) {
    var el = document.getElementById("trace-detail");
    if (!el) return;
    
    var t = traceStore[tid];
    if (!t) return;
    
    var h = `<div class="trace-detail-header">
                <h3>${t.name}</h3>
                <code style="font-size:11px;color:var(--on-surface-v)">${tid}</code>
             </div>
             <div class="trace-tree">`;
             
    // Build hierarchy
    var spans = t.spans;
    var roots = spans.filter(s => !s.parent_id || !spans.some(p => p.span_id === s.parent_id));
    
    if (roots.length === 0 && spans.length > 0) roots = [spans[0]]; // Fallback

    roots.forEach(r => {
        h += renderSpanNode(r, spans);
    });
    
    h += `</div>`;
    el.innerHTML = h;
}

function renderSpanNode(span, allSpans) {
    var children = allSpans.filter(s => s.parent_id === span.span_id);
    
    var duration = "";
    if (span.duration_ms !== undefined && span.duration_ms !== null) {
        duration = span.duration_ms === 0 ? "<1ms" : span.duration_ms + "ms";
    }
    
    var category = "SYS";
    if (span.data) {
        if (span.data['db.statement'] || span.data['sql']) {
            category = "SQL";
        } else if (span.data['http.url'] || span.data['http.method']) {
            category = "HTTP";
        } else if (span.category) {
            category = span.category;
        }
    }
    
    var color = "var(--primary)";
    if (span.lvl === "Error") {
        color = "var(--error)";
    } else if (category === "SQL") {
        color = "#29b6f6";
    } else if (category === "HTTP") {
        color = "#2ecc71";
    } else if (category === "APP") {
        color = "var(--warn)";
    }
    
    // Stringify span for click handler safely
    var escapedSpanStr = JSON.stringify(span)
                            .replace(/\\/g, '\\\\')
                            .replace(/'/g, "\\'")
                            .replace(/"/g, '&quot;');
    
    var contentHtml = `
        <div class="trace-node-content" style="border-left: 3px solid ${color}; cursor: pointer" onclick="openInspector('${escapedSpanStr}')">
            <span class="trace-tag cat-${category.toLowerCase()}" style="margin-right:8px;font-size:9px;padding:1px 5px;border-radius:4px;border:1px solid">${category}</span>
            <span class="trace-node-name">${span.msg}</span>
            <span class="trace-node-duration">${duration}</span>
        </div>
    `;
    
    var h = `<div class="trace-node">
                ${contentHtml}`;
                 
    if (children.length > 0) {
        h += `<div class="trace-node-children">`;
        children.forEach(c => {
            h += renderSpanNode(c, allSpans);
        });
        h += `</div>`;
    }
    
    h += `</div>`;
    return h;
}

function tracesClear() {
    traceStore = {};
    activeTraceId = null;
    updateAppFilters();
    renderTraceList();
    document.getElementById("trace-detail").innerHTML = '<div class="trace-empty-msg" data-i18n="select_trace">Select a trace to view details</div>';
    applyI18n();
}

var loadingHistory = false;
async function loadHistory() {
    try {
        loadingHistory = true;
        const r = await fetch("/api/telemetry/history");
        if (r.ok) {
            const history = await r.json();
            console.log("[loadHistory] Loaded " + history.length + " items from sidecar");
            history.forEach(function(item) {
                handleSseEvent(item.event, JSON.stringify(item.data));
            });
        }
    } catch(e) { console.warn("Failed to load telemetry history:", e); }
    finally {
        loadingHistory = false;
        updateAppFilters();
        renderLogs();
        renderTraceList();
        // Auto-select the most recent trace if none selected
        if (!activeTraceId) {
            var traceKeys = Object.keys(traceStore);
            if (traceKeys.length > 0) {
                var newest = traceKeys.sort(function(a,b) {
                    return new Date(traceStore[b].startTime) - new Date(traceStore[a].startTime);
                })[0];
                selectTrace(newest);
            }
        }
    }
}

// ==================== Init ====================
load();
// Prefer SignalR; index.html exposes DextSSE as fallback used by hub().
hub();

// ==================== Metrics & Charts (S25) ====================
var throughputChart = null;
var systemChart = null;
var maxChartPoints = 60;

function getMetricVal(metrics, name, key = 'value', defaultVal = 0) {
    if (!metrics) return defaultVal;
    var item = metrics.find(m => m.name === name);
    if (!item) return defaultVal;
    return item[key] !== undefined ? item[key] : defaultVal;
}

function initCharts() {
    var ctxT = document.getElementById('chart-throughput');
    var ctxS = document.getElementById('chart-system');
    if (!ctxT || !ctxS) return;

    var isLight = document.documentElement.classList.contains('light');
    var gridColor = isLight ? 'rgba(0, 0, 0, 0.05)' : 'rgba(255, 255, 255, 0.05)';
    var textColor = isLight ? '#5f6368' : '#e8eaed';

    Chart.defaults.color = textColor;
    Chart.defaults.font.family = "'Inter', sans-serif";

    throughputChart = new Chart(ctxT, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                {
                    label: 'HTTP RPS',
                    data: [],
                    borderColor: '#6200ee',
                    backgroundColor: 'rgba(98, 0, 238, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                },
                {
                    label: 'SQL QPS',
                    data: [],
                    borderColor: '#03dac6',
                    backgroundColor: 'rgba(3, 218, 198, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                },
                {
                    label: 'HTTP Errors',
                    data: [],
                    borderColor: '#cf6679',
                    backgroundColor: 'rgba(207, 102, 121, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                },
                {
                    label: 'Avg Latency (ms)',
                    data: [],
                    borderColor: '#ffb74d',
                    backgroundColor: 'transparent',
                    borderWidth: 1.5,
                    borderDash: [5, 5],
                    tension: 0.3,
                    yAxisID: 'y1'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: { boxWidth: 10, boxHeight: 10 }
                },
                tooltip: { mode: 'index', intersect: false }
            },
            scales: {
                x: {
                    grid: { color: gridColor },
                    ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 8 }
                },
                y: {
                    type: 'linear',
                    display: true,
                    position: 'left',
                    grid: { color: gridColor },
                    title: { display: true, text: 'RPS / QPS' },
                    min: 0
                },
                y1: {
                    type: 'linear',
                    display: true,
                    position: 'right',
                    grid: { drawOnChartArea: false },
                    title: { display: true, text: 'Latency (ms)' },
                    min: 0
                }
            }
        }
    });

    systemChart = new Chart(ctxS, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                {
                    label: 'CPU Usage (%)',
                    data: [],
                    borderColor: '#29b6f6',
                    backgroundColor: 'rgba(41, 182, 246, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                },
                {
                    label: 'Memory (MB)',
                    data: [],
                    borderColor: '#ab47bc',
                    backgroundColor: 'rgba(171, 71, 188, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y1'
                },
                {
                    label: 'DB Connections',
                    data: [],
                    borderColor: '#66bb6a',
                    backgroundColor: 'rgba(102, 187, 106, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                },
                {
                    label: 'Threads',
                    data: [],
                    borderColor: '#ffa726',
                    backgroundColor: 'rgba(255, 167, 38, 0.1)',
                    borderWidth: 2,
                    tension: 0.3,
                    yAxisID: 'y'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: { boxWidth: 10, boxHeight: 10 }
                },
                tooltip: { mode: 'index', intersect: false }
            },
            scales: {
                x: {
                    grid: { color: gridColor },
                    ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 8 }
                },
                y: {
                    type: 'linear',
                    display: true,
                    position: 'left',
                    grid: { color: gridColor },
                    title: { display: true, text: '% / Count' },
                    min: 0
                },
                y1: {
                    type: 'linear',
                    display: true,
                    position: 'right',
                    grid: { drawOnChartArea: false },
                    title: { display: true, text: 'Memory (MB)' },
                    min: 0
                }
            }
        }
    });
}

function updateChartsTheme() {
    if (!throughputChart || !systemChart) return;
    var isLight = document.documentElement.classList.contains('light');
    var gridColor = isLight ? 'rgba(0, 0, 0, 0.05)' : 'rgba(255, 255, 255, 0.05)';
    var textColor = isLight ? '#5f6368' : '#e8eaed';

    [throughputChart, systemChart].forEach(chart => {
        chart.options.scales.x.grid.color = gridColor;
        chart.options.scales.y.grid.color = gridColor;
        chart.options.scales.x.ticks.color = textColor;
        chart.options.scales.y.ticks.color = textColor;
        if (chart.options.scales.y1) {
            chart.options.scales.y1.ticks.color = textColor;
        }
        chart.update();
    });
}

function addMetricPoint(payload) {
    if (!throughputChart || !systemChart) return;

    var time = new Date(payload.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    
    // Throughput data
    var httpRequests = getMetricVal(payload.metrics, 'http.requests', 'value', 0);
    var sqlQueries = getMetricVal(payload.metrics, 'sql.queries', 'value', 0);
    var httpErrors = getMetricVal(payload.metrics, 'http.errors', 'value', 0);
    var avgLatency = getMetricVal(payload.metrics, 'http.latency', 'avg', 0);

    var httpRps = parseFloat((httpRequests / 5.0).toFixed(2));
    var sqlQps = parseFloat((sqlQueries / 5.0).toFixed(2));
    var httpErrorsRps = parseFloat((httpErrors / 5.0).toFixed(2));
    avgLatency = parseFloat(avgLatency.toFixed(1));

    // System data
    var cpu = payload.system ? parseFloat((payload.system.cpu || 0).toFixed(1)) : 0;
    var memory = payload.system ? parseFloat(((payload.system.memory_working_set || 0) / (1024 * 1024)).toFixed(1)) : 0;
    var dbConn = payload.system ? (payload.system.db_connections || 0) : 0;
    var threads = payload.system ? (payload.system.threads || 0) : 0;

    function pushData(chart, label, dataList) {
        chart.data.labels.push(label);
        if (chart.data.labels.length > maxChartPoints) {
            chart.data.labels.shift();
        }
        
        for (var i = 0; i < dataList.length; i++) {
            chart.data.datasets[i].data.push(dataList[i]);
            if (chart.data.datasets[i].data.length > maxChartPoints) {
                chart.data.datasets[i].data.shift();
            }
        }
        chart.update('none');
    }

    pushData(throughputChart, time, [httpRps, sqlQps, httpErrorsRps, avgLatency]);
    pushData(systemChart, time, [cpu, memory, dbConn, threads]);
}

async function loadMetricsHistory() {
    try {
        var r = await fetch('/api/telemetry/metrics/history');
        if (r.ok) {
            var history = await r.json();
            if (Array.isArray(history)) {
                history.forEach(payload => {
                    if (payload && payload.timestamp) {
                        addMetricPointToDataOnly(payload);
                    }
                });
                if (throughputChart) throughputChart.update();
                if (systemChart) systemChart.update();
            }
        }
    } catch(e) {
        console.warn("Failed to load metrics history:", e);
    }
}

function addMetricPointToDataOnly(payload) {
    if (!throughputChart || !systemChart) return;

    var time = new Date(payload.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    
    // Throughput data
    var httpRequests = getMetricVal(payload.metrics, 'http.requests', 'value', 0);
    var sqlQueries = getMetricVal(payload.metrics, 'sql.queries', 'value', 0);
    var httpErrors = getMetricVal(payload.metrics, 'http.errors', 'value', 0);
    var avgLatency = getMetricVal(payload.metrics, 'http.latency', 'avg', 0);

    var httpRps = parseFloat((httpRequests / 5.0).toFixed(2));
    var sqlQps = parseFloat((sqlQueries / 5.0).toFixed(2));
    var httpErrorsRps = parseFloat((httpErrors / 5.0).toFixed(2));
    avgLatency = parseFloat(avgLatency.toFixed(1));

    // System data
    var cpu = payload.system ? parseFloat((payload.system.cpu || 0).toFixed(1)) : 0;
    var memory = payload.system ? parseFloat(((payload.system.memory_working_set || 0) / (1024 * 1024)).toFixed(1)) : 0;
    var dbConn = payload.system ? (payload.system.db_connections || 0) : 0;
    var threads = payload.system ? (payload.system.threads || 0) : 0;

    function pushDataOnly(chart, label, dataList) {
        chart.data.labels.push(label);
        if (chart.data.labels.length > maxChartPoints) {
            chart.data.labels.shift();
        }
        for (var i = 0; i < dataList.length; i++) {
            chart.data.datasets[i].data.push(dataList[i]);
            if (chart.data.datasets[i].data.length > maxChartPoints) {
                chart.data.datasets[i].data.shift();
            }
        }
    }

    pushDataOnly(throughputChart, time, [httpRps, sqlQps, httpErrorsRps, avgLatency]);
    pushDataOnly(systemChart, time, [cpu, memory, dbConn, threads]);
}

function openInspector(spanStr) {
    try {
        var span = JSON.parse(spanStr);
        console.log("Opening inspector for span:", span);

        var drawer = document.getElementById("inspector-drawer");
        if (!drawer) return;

        // Reset display sections
        document.getElementById("drawer-error-section").style.display = "none";
        document.getElementById("drawer-sql-section").style.display = "none";
        document.getElementById("drawer-http-section").style.display = "none";

        // Fill overview metadata
        var duration = "";
        if (span.duration_ms !== undefined && span.duration_ms !== null) {
            duration = span.duration_ms === 0 ? "<1ms" : span.duration_ms + "ms";
        }
        document.getElementById("drawer-meta-name").textContent = span.msg || "-";
        document.getElementById("drawer-meta-duration").textContent = duration || "-";
        
        var category = "SYS";
        if (span.data) {
            if (span.data['db.statement'] || span.data['sql']) {
                category = "SQL";
            } else if (span.data['http.url'] || span.data['http.method']) {
                category = "HTTP";
            } else if (span.category) {
                category = span.category;
            }
        }
        
        var catEl = document.getElementById("drawer-meta-category");
        catEl.textContent = category;
        catEl.className = "trace-tag cat-" + category.toLowerCase();

        var statusEl = document.getElementById("drawer-meta-status");
        if (span.lvl === "Error") {
            statusEl.textContent = "Failed";
            statusEl.style.color = "var(--error)";
            
            // Show error section
            document.getElementById("drawer-error-section").style.display = "block";
            document.getElementById("drawer-error-text").textContent = span.data && span.data.error ? span.data.error : "Unknown error occurred";
        } else {
            statusEl.textContent = "Success";
            statusEl.style.color = "var(--success)";
        }

        // Category specific details
        if (category === "SQL") {
            document.getElementById("drawer-sql-section").style.display = "block";
            var sqlText = span.data ? (span.data.sql || span.data['db.statement'] || "") : "";
            document.getElementById("drawer-sql-text").textContent = sqlText;
            
            var sqlParams = span.data ? (span.data.params || span.data['db.params'] || span.data['db.param'] || span.data['dh.param'] || "{}") : "{}";
            // If it's a string representing JSON, try to pretty print it
            try {
                if (typeof sqlParams === 'string') {
                    var parsed = JSON.parse(sqlParams);
                    document.getElementById("drawer-sql-params").textContent = JSON.stringify(parsed, null, 2);
                } else {
                    document.getElementById("drawer-sql-params").textContent = JSON.stringify(sqlParams, null, 2);
                }
            } catch(e) {
                document.getElementById("drawer-sql-params").textContent = sqlParams;
            }

            // Copy SQL button
            document.getElementById("drawer-copy-sql").onclick = function(e) {
                e.stopPropagation();
                navigator.clipboard.writeText(sqlText);
                alert("SQL copied to clipboard!");
            };
        } else if (category === "HTTP") {
            document.getElementById("drawer-http-section").style.display = "block";
            var url = span.data ? (span.data.url || span.data['http.url'] || "") : "";
            var method = span.data ? (span.data.method || span.data['http.method'] || "GET") : "GET";
            var statusCode = span.data ? (span.data.statusCode || span.data['http.status_code'] || "-") : "-";

            document.getElementById("drawer-http-url").textContent = url;
            
            var methodEl = document.getElementById("drawer-http-method");
            methodEl.textContent = method;
            methodEl.className = "trace-tag cat-http";

            var statusHttpEl = document.getElementById("drawer-http-status");
            statusHttpEl.textContent = statusCode;
            if (parseInt(statusCode) >= 400) {
                statusHttpEl.style.borderColor = "var(--error)";
                statusHttpEl.style.color = "var(--error)";
            } else {
                statusHttpEl.style.borderColor = "#2ecc71";
                statusHttpEl.style.color = "#2ecc71";
            }

            // Copy as cURL button
            document.getElementById("drawer-copy-curl").onclick = function(e) {
                e.stopPropagation();
                var curl = `curl -X ${method} "${url}"`;
                navigator.clipboard.writeText(curl);
                alert("cURL command copied to clipboard!");
            };
        }

        // Generic Attributes & Metadata
        var tagsContainer = document.getElementById("drawer-generic-tags");
        tagsContainer.innerHTML = "";
        if (span.data) {
            Object.keys(span.data).forEach(k => {
                // Skip sql, params, url, method, statusCode, error since they have custom visual blocks
                if (['sql', 'db.statement', 'params', 'db.params', 'url', 'http.url', 'method', 'http.method', 'statusCode', 'http.status_code', 'error'].includes(k)) return;
                
                var val = span.data[k];
                if (val === undefined || val === null || val === "") return;
                
                var spanTag = document.createElement("span");
                spanTag.className = "trace-tag";
                spanTag.innerHTML = `<strong>${k}:</strong> ${val}`;
                tagsContainer.appendChild(spanTag);
            });
        }

        // Open the drawer
        drawer.classList.add("open");
    } catch(e) {
        console.error("Failed to open inspector:", e);
    }
}

function closeInspector() {
    var drawer = document.getElementById("inspector-drawer");
    if (drawer) {
        drawer.classList.remove("open");
    }
}


