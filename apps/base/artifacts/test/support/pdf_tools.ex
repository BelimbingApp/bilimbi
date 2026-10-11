defmodule Bilimbi.Base.Artifacts.PDFTestTools do
  @moduledoc false

  # Small executable fixtures prove public engine outcomes, including missing,
  # failed and timed-out processes. Real engine checks are opt-in below.
  def qpdf(dir, result \\ :success) do
    path = Path.join(dir, "qpdf")

    body =
      case result do
        :failure ->
          "process.exit(2);"

        :timeout ->
          "setInterval(() => {}, 1000);"

        :empty ->
          "const j = JSON.parse(fs.readFileSync(process.argv[2].slice(16))); fs.writeFileSync(j.outputFile, '');"

        :success ->
          """
          const j = JSON.parse(fs.readFileSync(process.argv[2].slice(16)));
          if (j.encrypt.userPassword === '' || j.encrypt.ownerPassword === '' || !j.encrypt['256bit']) process.exit(2);
          fs.writeFileSync(j.outputFile, Buffer.concat([Buffer.from('%PDF-protected\\n'), fs.readFileSync(j.inputFile)]));
          """
      end

    File.write!(path, "#!/usr/bin/env node\nconst fs = require('node:fs');\n" <> body)
    File.chmod!(path, 0o700)
    path
  end

  def chromium(dir, pdf) do
    path = Path.join(dir, "chromium")

    File.write!(path, """
    #!/usr/bin/env node
    const fs = require('node:fs');
    const input = fs.createReadStream(null, {fd: 3});
    const output = fs.createWriteStream(null, {fd: 4});
    let buffered = '', scriptDisabled = false, intercepted = false;
    const emit = m => output.write(JSON.stringify(m) + '\\0');
    input.on('data', chunk => {
      buffered += chunk.toString();
      let end;
      while ((end = buffered.indexOf('\\0')) !== -1) {
        const m = JSON.parse(buffered.slice(0, end));
        buffered = buffered.slice(end + 1);
        let result = {};
        if (m.method === 'Target.createTarget') result = {targetId: 'target'};
        if (m.method === 'Target.attachToTarget') result = {sessionId: 'session'};
        if (m.method === 'Page.getFrameTree') result = {frameTree: {frame: {id: 'frame'}}};
        if (m.method === 'Emulation.setScriptExecutionDisabled') scriptDisabled = m.params.value;
        if (m.method === 'Fetch.enable') intercepted = true;
        if (m.method === 'Page.printToPDF') {
          if (!scriptDisabled || !intercepted || !m.params.paperWidth) process.exit(2);
          result = {data: '#{Base.encode64(pdf)}'};
        }
        emit({id: m.id, result});
        if (m.method === 'Page.setDocumentContent' || m.method === 'Page.navigate') {
          emit({sessionId: 'session', method: 'Network.responseReceived', params: {type: 'Document', response: {status: 200}}});
          emit({sessionId: 'session', method: 'Page.loadEventFired'});
        }
      }
    });
    """)

    File.chmod!(path, 0o700)
    path
  end
end
