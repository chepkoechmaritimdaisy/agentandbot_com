defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically tracks and updates SKILL.md for tools and functions.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every minute
  @skill_file "SKILL.md"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def update_skills do
    Logger.info("Starting SkillTracker update...")

    # Load existing skills to avoid duplicates
    existing_skills = load_existing_skills()

    # Get all loaded modules
    all_modules = Code.all_loaded() |> Enum.map(fn {mod, _} -> mod end)

    # Filter modules that are tools or functions (simplified heuristic)
    # We look for modules with public functions that have documentation
    modules_with_docs =
      all_modules
      |> Enum.filter(fn mod ->
        # We only care about our own modules
        String.starts_with?(to_string(mod), "Elixir.GovernanceCore")
      end)

    # Extract docs and generate entries
    new_entries =
      Enum.reduce(modules_with_docs, [], fn mod, acc ->
        case Code.fetch_docs(mod) do
          {:docs_v1, _, _, _, _, _, docs} ->
            module_entries =
              docs
              |> Enum.filter(fn {{type, _func, _arity}, _, _, doc, _} ->
                type == :function and doc != :none and doc != %{}
              end)
              |> Enum.map(fn {{_, func, arity}, _, _, %{"en" => doc_string}, _} ->
                # Generate YAML frontmatter
                entry = """
                ---
                tool: #{mod}.#{func}/#{arity}
                ---
                #{String.slice(doc_string, 0, 1024)}
                """
                {mod, func, arity, entry}
              end)
            acc ++ module_entries
          _ ->
            acc
        end
      end)

    # Write new entries
    entries_to_write =
      new_entries
      |> Enum.filter(fn {mod, func, arity, _entry} ->
        not MapSet.member?(existing_skills, "#{mod}.#{func}/#{arity}")
      end)
      |> Enum.map(fn {_, _, _, entry} -> entry end)

    if not Enum.empty?(entries_to_write) do
      Logger.info("Appending #{length(entries_to_write)} new skills to #{@skill_file}")
      # Append to SKILL.md
      File.open(@skill_file, [:append, :utf8], fn file ->
        Enum.each(entries_to_write, fn entry ->
          IO.puts(file, "\n" <> entry)
        end)
      end)
    end
  end

  defp load_existing_skills do
    # Simple extraction of tool names from YAML frontmatter
    case File.read(@skill_file) do
      {:ok, content} ->
        # Use regex to find `tool: Module.func/arity`
        Regex.scan(~r/tool:\s+([^\n]+)/, content)
        |> Enum.map(fn [_, tool] -> String.trim(tool) end)
        |> MapSet.new()
      {:error, :enoent} ->
        MapSet.new()
      {:error, reason} ->
        Logger.error("Failed to read #{@skill_file}: #{inspect(reason)}")
        MapSet.new()
    end
  end
end
