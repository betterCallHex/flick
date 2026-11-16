enum PhonePage {
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="color-scheme" content="dark">
    <title>Flick</title>
    <style>
    :root { --bg: #121212; --card: #1e1e1e; --text: #f2f2f2; --muted: #9a9a9a; --accent: #ffffff; --bar: #3a3a3a; --bad: #ff6b6b; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--text);
      font: 17px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex; flex-direction: column; align-items: center; padding: 32px 16px; }
    main { width: 100%; max-width: 420px; display: flex; flex-direction: column; gap: 16px; }
    h1 { font-size: 24px; margin: 0 0 4px; }
    p { margin: 0; color: var(--muted); }
    section { background: var(--card); border-radius: 16px; padding: 18px; display: flex; flex-direction: column; gap: 12px; }
    button, .pick { appearance: none; border: 0; border-radius: 12px; padding: 14px; font: inherit; font-weight: 600;
      background: var(--accent); color: #000; text-align: center; cursor: pointer; }
    button:disabled { opacity: .4; }
    input[type=url] { font: inherit; padding: 12px; border-radius: 12px; border: 1px solid var(--bar); background: var(--bg); color: var(--text); width: 100%; }
    input[type=file] { display: none; }
    progress { width: 100%; height: 8px; appearance: none; border: 0; border-radius: 4px; overflow: hidden; background: var(--bar); }
    progress::-webkit-progress-bar { background: var(--bar); }
    progress::-webkit-progress-value { background: var(--accent); }
    progress::-moz-progress-bar { background: var(--accent); }
    #status { min-height: 1.4em; }
    .bad { color: var(--bad); }
    [hidden] { display: none !important; }
    </style>
    </head>
    <body>
    <main>
      <div>
        <h1>Play on your Mac</h1>
        <p>Pick a video and it starts playing in Flick.</p>
      </div>
      <section>
        <label class="pick" for="file">Choose a video</label>
        <input id="file" type="file" accept="video/*,audio/*">
        <progress id="progress" max="1" value="0" hidden></progress>
        <p id="status"></p>
      </section>
      <section>
        <p>Or play a link (YouTube, Vimeo, a .mp4…)</p>
        <form id="link-form">
          <input id="link" type="url" placeholder="https://" required>
        </form>
        <button form="link-form" type="submit">Play link</button>
        <p id="link-status"></p>
      </section>
    </main>
    <script>
    const base = location.pathname.replace(/\\/?$/, "/");
    const picker = document.getElementById("file");
    const bar = document.getElementById("progress");
    const status = document.getElementById("status");
    const pickLabel = document.querySelector(".pick");
    let wakeLock = null;

    function say(element, text, isBad) {
      element.textContent = text;
      element.classList.toggle("bad", Boolean(isBad));
    }

    async function keepAwake() {
      try { wakeLock = await navigator.wakeLock.request("screen"); } catch (error) { wakeLock = null; }
    }

    function letSleep() {
      if (wakeLock) wakeLock.release();
      wakeLock = null;
    }

    picker.addEventListener("change", () => {
      const file = picker.files[0];
      if (!file) return;
      const request = new XMLHttpRequest();
      request.open("PUT", base + "upload?name=" + encodeURIComponent(file.name));
      request.upload.onprogress = (event) => {
        if (!event.lengthComputable) return;
        bar.value = event.loaded / event.total;
        say(status, "Sending to your Mac… " + Math.floor(100 * event.loaded / event.total) + "%. Keep this page open.");
      };
      request.onload = () => {
        letSleep();
        pickLabel.hidden = false;
        bar.hidden = true;
        if (request.status === 200) say(status, "Done. “" + file.name + "” is playing on your Mac.");
        else say(status, "Your Mac couldn’t save this video.", true);
      };
      request.onerror = () => {
        letSleep();
        pickLabel.hidden = false;
        bar.hidden = true;
        say(status, "The upload stopped. Flick moved on to something else, or the Mac went to sleep.", true);
      };
      keepAwake();
      pickLabel.hidden = true;
      bar.hidden = false;
      bar.value = 0;
      say(status, "Starting…");
      request.send(file);
      picker.value = "";
    });

    document.getElementById("link-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      const linkStatus = document.getElementById("link-status");
      const field = document.getElementById("link");
      try {
        const response = await fetch(base + "link", { method: "POST", body: field.value.trim() });
        if (response.ok) {
          say(linkStatus, "Playing on your Mac.");
          field.value = "";
        } else {
          say(linkStatus, "That doesn’t look like a web link.", true);
        }
      } catch (error) {
        say(linkStatus, "Couldn’t reach your Mac.", true);
      }
    });
    </script>
    </body>
    </html>
    """
}
