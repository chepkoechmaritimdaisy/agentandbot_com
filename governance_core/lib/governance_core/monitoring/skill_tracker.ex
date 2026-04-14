defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks tools/modules in the project and standardizes SKILL.md.
  Runs continuously to keep documentation up to date.
  """
  use GenServer
  require Logger

  # 5 minutes in ms
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_track()
    {:ok, state}
  end

  @impl true
  def handle_info(:track, state) do
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp perform_track do
    Logger.info("Starting Skill Tracking...")

    # Discover modules
    {:ok, modules} = :application.get_key(:governance_core, :modules)

    tools =
      Enum.map(modules, fn mod ->
        mod_name = inspect(mod)
        doc = get_module_doc(mod)
        "  - name: #{mod_name}\n    doc: |\n" <> indent_doc(doc)
      end)
      |> Enum.join("\n")

    yaml_content = "skills:\n" <> tools

    # Enforce 1024-character limit and truncate at the last newline cleanly
    truncated_content =
      if String.length(yaml_content) > 1024 do
        yaml_content
        |> String.slice(0, 1024)
        |> String.replace(~r/\n[^\n]*$/, "\n")
      else
        yaml_content
      end

    priv_dir = :code.priv_dir(:governance_core)
    skill_file = Path.join(priv_dir, "SKILL.md")

    File.write!(skill_file, truncated_content)
    Logger.info("Skill Tracker updated SKILL.md in priv.")
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} -> doc
      _ -> "No documentation available."
    end
  end

  defp indent_doc(doc) do
    doc
    |> String.split("\n")
    |> Enum.map(fn line -> "      " <> line end)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end
end
