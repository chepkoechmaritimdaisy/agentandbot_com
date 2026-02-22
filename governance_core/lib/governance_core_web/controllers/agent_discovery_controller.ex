defmodule GovernanceCoreWeb.AgentDiscoveryController do
  use GovernanceCoreWeb, :controller

  def show(conn, _params) do
    discovery_data = %{
      schema_version: "1.0",
      name: "agentandbot.com",
      description: "Enterprise Agent OS — deploy AI agents that work like digital employees.",
      contact: "admin@agentandbot.com",
      protocol: %{
        name: "ABL.ONE",
        version: "1.0",
        description: "8-byte binary frame protocol for ultra-fast agent-to-agent communication.",
        frame_size: "8B",
        encoding: "Gibberlink",
        checksum: "CRC32",
        repository: "https://github.com/agentandbot-design/dil"
      },
      endpoints: %{
        handshake: "/agent/connect",
        api_base: "/api",
        agents: "/api/agents",
        tasks: "/api/tasks"
      },
      auth: %{
        method: "OAuth 2.1 M2M",
        token_type: "JWT",
        token_endpoint: "/oauth/token"
      },
      capabilities: [
        "agent_discovery",
        "agent_deployment",
        "task_assignment",
        "m2m_communication",
        "binary_protocol"
      ],
      rules_of_engagement: [
        "All transactions are logged and CRC32 verified.",
        "Resource quotas are strictly enforced.",
        "Unauthenticated agents run in sandbox mode.",
        "Binary frames only — no plaintext in transit."
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(discovery_data)
  end
end
