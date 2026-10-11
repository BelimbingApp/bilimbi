defmodule Bilimbi.Base.Artifacts.PDFTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.{Artifacts, Settings, Tenancy}
  alias Bilimbi.Base.Artifacts.{PDF, PDFTestTools, TestPDFOwner}
  alias Bilimbi.Base.Artifacts.PDF.{Artifact, Engine, Rendered, Renderer, RenderWorker}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue.Execution
  import Bilimbi.Base.Artifacts.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures
  import Bilimbi.Base.Settings.TestFixtures
  import Bilimbi.Base.Audit.TestFixtures

  setup do
    settings =
      Bilimbi.Base.Settings.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/artifacts"},
          payload: Bilimbi.Base.Artifacts.Contributions.contributions().settings
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{settings: settings})
    on_exit(&ContributionRegistry.clear_for_test!/0)
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    create_settings_table!()
    create_audit_tables!()
    create_artifacts_table!()
    root = Path.join(System.tmp_dir!(), "pdf-test-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    Settings.put("artifacts.storage_root", root)
    Settings.put("artifacts.retention_days", 30)
    Settings.put("pdf.qpdf.binary", PDFTestTools.qpdf(root))
    {:ok, scope} = Tenancy.scope(41)
    {:ok, bytes} = Renderer.render(%{title: "Source", blocks: [{:text, "private facts"}]})
    %{scope: scope, root: root, bytes: bytes, ref: %{subject: "record-1", kind: "report"}}
  end

  test "writer stores a PDF through Artifacts with digest and actor provenance", c do
    assert {:ok, artifact} =
             PDF.persist(c.scope, 51, TestPDFOwner, c.ref, c.bytes,
               template_version: "v2",
               data_version: "data-7"
             )

    assert {:ok, %{bytes: bytes}} =
             Artifacts.read(c.scope, 51, TestPDFOwner, artifact.document.id)

    assert bytes == c.bytes
    assert artifact.template_version == "v2"
    assert artifact.data_version == "data-7"
    assert artifact.produced_by == nil

    assert Artifact.to_map(artifact).sha256 ==
             Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    refute Map.has_key?(Artifact.to_map(artifact), :path)
    refute Map.has_key?(Artifact.to_map(artifact), :storage_root)
  end

  test "writer refuses invalid PDFs, invalid provenance, oversized output and wrong companies",
       c do
    assert {:error, :invalid_pdf} = PDF.persist(c.scope, 51, TestPDFOwner, c.ref, "HTML")

    assert {:error, :invalid_pdf_options} =
             PDF.persist(c.scope, 51, TestPDFOwner, c.ref, c.bytes, data_version: 5)

    assert {:error, :forbidden} = PDF.persist(c.scope, 99, TestPDFOwner, c.ref, c.bytes)
    Settings.put("artifacts.max_bytes", 3)
    assert {:error, :invalid_size} = PDF.persist(c.scope, 51, TestPDFOwner, c.ref, c.bytes)
  end

  test "password protection creates a new artifact and preserves the authorized source", c do
    {:ok, source} =
      PDF.persist(c.scope, 51, TestPDFOwner, c.ref, c.bytes, data_version: "original")

    assert {:ok, encrypted} =
             PDF.protect_with_password(
               c.scope,
               51,
               TestPDFOwner,
               source,
               "user-secret",
               "owner-secret"
             )

    assert encrypted.document.id != source.document.id
    assert encrypted.data_version == "original (encrypted)"
    assert encrypted.template_version == source.template_version
    assert encrypted.produced_by == source.produced_by
    assert {:ok, %{bytes: plain}} = Artifacts.read(c.scope, 51, TestPDFOwner, source.document.id)
    assert plain == c.bytes

    assert {:ok, %{bytes: protected}} =
             Artifacts.read(c.scope, 51, TestPDFOwner, encrypted.document.id)

    assert protected != plain

    assert {:error, :empty_password} =
             PDF.protect_with_password(c.scope, 51, TestPDFOwner, source, "")

    Process.put({:deny, :read}, true)

    assert {:error, :forbidden} =
             PDF.protect_with_password(c.scope, 51, TestPDFOwner, source, "secret")
  end

  test "publication authorization is rechecked after processing", c do
    Process.put(:deny_create_after, 2)

    assert {:error, :forbidden} =
             PDF.persist(c.scope, 51, TestPDFOwner, c.ref, c.bytes, password: "secret")
  end

  test "qpdf missing, failure, empty output and timeout return safe errors", c do
    assert PDF.protection_available?()
    Settings.put("pdf.qpdf.binary", Path.join(c.root, "missing"))
    refute PDF.protection_available?()
    assert {:error, :pdf_tool_unavailable} = Engine.protect(c.bytes, "secret", nil)
    Settings.put("pdf.qpdf.binary", PDFTestTools.qpdf(c.root, :failure))
    assert {:error, :pdf_engine_failed} = Engine.protect(c.bytes, "secret", nil)
    Settings.put("pdf.qpdf.binary", PDFTestTools.qpdf(c.root, :empty))
    assert {:error, :invalid_pdf} = Engine.protect(c.bytes, "secret", nil)
    Settings.put("pdf.qpdf.binary", PDFTestTools.qpdf(c.root, :timeout))
    Settings.put("pdf.qpdf.timeout_seconds", 1)
    assert {:error, :pdf_timeout} = Engine.protect(c.bytes, "secret", nil)
    refute File.exists?(Path.join(c.root, "source.pdf"))
  end

  test "inline generation authorizes before selecting template data", c do
    Process.put({:deny, :create}, true)

    assert {:error, :forbidden} =
             PDF.render_inline(c.scope, 51, TestPDFOwner, c.ref, %{html: "secret"})

    refute_received {:html_rendered, _}
  end

  test "signed view requires a configured origin", c do
    assert {:error, :render_origin_not_configured} =
             PDF.render_view(c.scope, 51, TestPDFOwner, c.ref, %{})

    assert PDF.valid_origin?("http://localhost:4000")
    assert PDF.valid_origin?("http://localhost:80/")
    refute PDF.valid_origin?("http://localhost:bad-port")
    refute PDF.valid_origin?("https://user:password@example.com")
    refute PDF.valid_origin?("file:///etc/passwd")
    refute PDF.valid_origin?("https://example.com/path")
    refute PDF.valid_origin?("https://example.com?token=secret")
  end

  test "worker args persist only references, refusing secrets and actor overrides" do
    args = %{
      "owner" => Atom.to_string(TestPDFOwner),
      "company_id" => 51,
      "subject" => "record-1",
      "kind" => "report",
      "request_id" => "req-1"
    }

    assert {:ok, ^args} = RenderWorker.validate_args(args)

    for field <- ["password", "data", "html", "actorUserId", "metadata"] do
      assert {:error, :invalid_request} =
               RenderWorker.validate_args(Map.put(args, field, "secret"))
    end

    assert {:error, :unknown_owner} =
             RenderWorker.validate_args(%{args | "owner" => "Nonexistent.Random.Owner"})

    assert {:cancel, :pdf_actor_unavailable} =
             RenderWorker.handle_job(args, %Execution{
               job_id: 1,
               attempt: 1,
               max_attempts: 3,
               queue: "default"
             })
  end

  test "worker resolves data live and sends completion with routing metadata", c do
    args = %{
      "owner" => Atom.to_string(TestPDFOwner),
      "company_id" => 51,
      "subject" => "record-1",
      "kind" => "report",
      "request_id" => "req-1"
    }

    execution = %Execution{
      job_id: 123,
      attempt: 1,
      max_attempts: 3,
      queue: "default",
      scope: c.scope
    }

    Process.put(:pdf_options, password: "secret", data_version: "current")
    assert :ok = RenderWorker.handle_job(args, execution)
    assert_received {:pdf_request, "req-1"}

    assert_received {:pdf_rendered,
                     %Rendered{
                       job_id: 123,
                       request_id: "req-1",
                       metadata: %{routing_id: "record-1"},
                       artifact: artifact
                     }}

    assert artifact.data_version == "current (encrypted)"
    assert {:ok, _} = Artifacts.read(c.scope, 51, TestPDFOwner, artifact.document.id)
    Process.put({:deny, :create}, true)
    assert {:cancel, :pdf_forbidden} = RenderWorker.handle_job(args, execution)
    refute_received {:pdf_rendered, _}
  end

  test "worker emits no completion for render failure", c do
    args = %{
      "owner" => Atom.to_string(TestPDFOwner),
      "company_id" => 51,
      "subject" => "record-1",
      "kind" => "report",
      "request_id" => "req-1"
    }

    execution = %Execution{
      job_id: 123,
      attempt: 1,
      max_attempts: 3,
      queue: "default",
      scope: c.scope
    }

    Settings.put("pdf.qpdf.binary", PDFTestTools.qpdf(c.root, :failure))
    Process.put(:pdf_options, password: "secret")
    assert {:retry, :pdf_render_failed} = RenderWorker.handle_job(args, execution)
    refute_received {:pdf_rendered, _}
  end

  test "inline rendering publishes browser output through the existing private writer", c do
    Settings.put("pdf.chromium.binary", PDFTestTools.chromium(c.root, c.bytes))

    assert {:ok, artifact} =
             PDF.render_inline(c.scope, 51, TestPDFOwner, c.ref, %{html: "<p>Private</p>"})

    assert_received {:html_rendered, _}

    assert {:ok, %{bytes: bytes}} =
             Artifacts.read(c.scope, 51, TestPDFOwner, artifact.document.id)

    assert bytes == c.bytes
    assert {:error, :invalid_html} = Engine.render({:html, nil})
  end

  test "signed view revokes unused claims after successful and failed browser rendering", c do
    Settings.put("pdf.render_origin", "http://localhost:4000")
    Settings.put("pdf.chromium.binary", PDFTestTools.chromium(c.root, c.bytes))
    assert {:ok, _} = PDF.render_view(c.scope, 51, TestPDFOwner, c.ref, %{html: "private"})
    Settings.put("pdf.chromium.binary", Path.join(c.root, "missing"))

    assert {:error, :pdf_tool_unavailable} =
             PDF.render_view(c.scope, 51, TestPDFOwner, c.ref, %{html: "private"})

    # Every render releases its reservation, including tool failure.
    assert {:ok, token} = Bilimbi.Base.Artifacts.PDF.Tokens.issue(%{}, 60, 1)
    Bilimbi.Base.Artifacts.PDF.Tokens.revoke(token)
  end

  @tag :pdf_tools
  test "real Chromium produces Unicode PDF and real qpdf protects it with AES-256", c do
    chromium = System.fetch_env!("PDF_TEST_CHROMIUM")
    qpdf = System.fetch_env!("PDF_TEST_QPDF")
    Settings.put("pdf.chromium.binary", chromium)
    Settings.put("pdf.qpdf.binary", qpdf)

    assert {:ok, bytes} =
             Engine.render(
               {:html,
                "<!doctype html><html><body><h1>Résumé 中文</h1><table><tr><td>12.50</td></tr></table></body></html>"}
             )

    assert {:ok, protected} = Engine.protect(bytes, "pdf-user-secret", "pdf-owner-secret")
    file = Path.join(c.root, "real.pdf")
    password_file = Path.join(c.root, "password")
    File.write!(file, protected)
    File.write!(password_file, "pdf-user-secret")
    File.chmod!(password_file, 0o600)

    assert {encryption, 0} =
             System.cmd(qpdf, ["--password-file=" <> password_file, "--show-encryption", file])

    assert encryption =~ "AESv3"
    assert {_report, 0} = System.cmd(qpdf, ["--password-file=" <> password_file, "--check", file])
    File.write!(password_file, "wrong-password")

    assert {_report, 2} =
             System.cmd(qpdf, ["--password-file=" <> password_file, "--check", file],
               stderr_to_stdout: true
             )
  end
end
