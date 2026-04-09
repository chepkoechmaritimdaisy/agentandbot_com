defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers all modules in the application and generates YAML documentation (SKILL.md)
  for tools and functions, ensuring evarsial standard (1024-character limit).
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        Enum.each(modules, fn mod ->
          generate_skill_doc(mod)
        end)
      _ ->
        Logger.error("Failed to retrieve application modules for skill tracking")
    end
  end

  defp generate_skill_doc(mod) do
    # Only process modules that start with GovernanceCore
    mod_string = inspect(mod)
    if String.starts_with?(mod_string, "GovernanceCore") do
      module_name_clean = String.replace(mod_string, "GovernanceCore.", "") |> String.replace(".", "_") |> String.downcase()
      dir_path = "skills/#{module_name_clean}"
      File.mkdir_p!(dir_path)

      file_path = Path.join(dir_path, "SKILL.md")

      doc = get_module_doc(mod)

      # Enforce 1024 character limit, correctly formatting yaml
      truncated_doc = String.slice(doc, 0, 950)

      # Proper YAML indentation for multiline string
      yaml_doc =
        truncated_doc
        |> String.split("\n")
        |> Enum.map(&("  " <> &1))
        |> Enum.join("\n")

      yaml_content = """
      ---
      module: #{mod_string}
      description: |
      #{yaml_doc}
      ---
      """

      # Only write if it's new or different to avoid unnecessary I/O
      current_content = if File.exists?(file_path), do: File.read!(file_path), else: ""
      if current_content != yaml_content do
         File.write!(file_path, yaml_content)
      end
    end
  end

  defp get_module_doc(mod) do
    # Try to extract module doc safely. If unavailable, return a default string.
    try do
      case Code.fetch_docs(mod) do
        {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc_str}, _, _} -> doc_str
        _ -> "No documentation available for #{inspect(mod)}"
      end
    rescue
      _ -> "No documentation available for #{inspect(mod)} (error fetching)"
    end
  end
end
