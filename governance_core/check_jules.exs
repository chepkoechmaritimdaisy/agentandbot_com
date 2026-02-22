# Professional Jules session check script
case GovernanceCore.JulesClient.list_sessions() do
  {:ok, %{"sessions" => sessions}} ->
    IO.puts("JULES SESSIONS:")

    Enum.each(sessions, fn s ->
      IO.puts("- ID: #{s["id"]}")
      IO.puts("  Title: #{s["title"]}")
      IO.puts("  State: #{s["state"]}")
      IO.puts("  Branch: #{get_in(s, ["sourceContext", "githubRepoContext", "startingBranch"])}")

      # Try to find PR URL
      outputs = s["outputs"] || []

      Enum.each(outputs, fn out ->
        if pr = out["pullRequest"] do
          IO.puts("  PR: #{pr["url"]}")
        end
      end)

      IO.puts("")
    end)

  {:error, reason} ->
    IO.inspect(reason, label: "Error fetching sessions")
end
