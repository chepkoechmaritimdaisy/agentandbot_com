defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically scans application modules and generates standard SKILL.md
  YAML files for tools and capabilities, enforcing a 1024 character limit.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Ensure skills directory exists
    File.mkdir_p!("skills")
    schedule_scan()
    {:ok, state}
  end

  def handle_info(:scan, state) do
    generate_skills()
    schedule_scan()
    {:noreply, state}
  end

  defp schedule_scan do
    Process.send_after(self(), :scan, @interval)
  end

  defp generate_skills do
    Logger.info("Starting SKILL.md generation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        Enum.each(modules, &process_module/1)
      _ ->
        Logger.error("Failed to fetch modules for governance_core")
    end
  end

  defp process_module(module) do
    module_name = inspect(module)

    # We only care about modules that might be tools/skills
    if String.starts_with?(module_name, "GovernanceCore.") do
      case Code.fetch_docs(module) do
        {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc_str}, _, _} ->
          write_skill_file(module_name, doc_str)
        _ ->
          # No docs or different format
          :ok
      end
    end
  end

  defp write_skill_file(module_name, doc_str) do
    # Enforce 1024 char limit and format for YAML multiline
    truncated_doc = String.slice(doc_str, 0, 1024)

    # Indent for YAML block scalar
    indented_doc =
      truncated_doc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    dir_path = "skills/#{module_name}"
    File.mkdir_p!(dir_path)

    yaml_content = """
    ---
    name: #{module_name}
    description: |
    #{indented_doc}
    ---
    """

    File.write!(Path.join(dir_path, "SKILL.md"), yaml_content)
  end
end
