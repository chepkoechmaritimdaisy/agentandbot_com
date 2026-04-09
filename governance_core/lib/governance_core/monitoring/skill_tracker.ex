defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks tools/skills in the codebase and generates
  SKILL.md documentation in YAML format.
  """
  use GenServer
  require Logger

  # Default interval: 1 hour
  @interval 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting SkillTracker")
    schedule_scan()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:scan, state) do
    scan_and_generate_skills()
    schedule_scan()
    {:noreply, state}
  end

  defp schedule_scan do
    Process.send_after(self(), :scan, @interval)
  end

  defp scan_and_generate_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Find tools, handlers, or agents that might be considered "skills"
        skills = Enum.filter(modules, fn mod ->
          name = to_string(mod)
          String.contains?(name, "GovernanceCore") &&
          (String.contains?(name, "Protocols") || String.contains?(name, "Monitoring") || String.contains?(name, "Agents"))
        end)

        Enum.each(skills, &generate_skill_md/1)
      _ ->
        Logger.warning("SkillTracker: Could not get modules for application")
    end
  end

  defp generate_skill_md(module) do
    module_name = module |> to_string() |> String.split(".") |> List.last() |> String.downcase()

    # In production, writing to the source tree is typically not possible/desirable.
    # We use the priv directory instead, which is guaranteed to be available and writable
    # in standard deployments (if persistent storage is attached) or at least safe to try.
    base_dir = case :code.priv_dir(:governance_core) do
      path when is_list(path) or is_binary(path) -> to_string(path)
      _ -> "skills_fallback"
    end

    dir_path = Path.join([base_dir, "skills", module_name])
    file_path = Path.join(dir_path, "SKILL.md")

    # Get documentation or default description
    # Note: Code.fetch_docs may fail in releases where docs are stripped.
    docs = case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => mod_doc}, _, _} -> mod_doc
      _ -> "Auto-generated skill documentation for #{module_name}."
    end

    # Truncate content to 1024 characters
    truncated_docs = String.slice(docs, 0, 1024)

    # Explicitly indent strings line-by-line for YAML block scalars
    indented_docs = truncated_docs
                    |> String.split("\n")
                    |> Enum.map(fn line -> "  " <> line end)
                    |> Enum.join("\n")

    yaml_content = """
    ---
    name: #{module_name}
    description: |
    #{indented_docs}
    ---
    """

    try do
      # Create directory if it doesn't exist
      File.mkdir_p!(dir_path)
      File.write!(file_path, yaml_content)
    rescue
      e -> Logger.debug("SkillTracker: Could not write SKILL.md for #{module_name}: #{inspect(e)}")
    end
  end
end
