defmodule GovernanceCoreWeb.Layouts do
  @moduledoc """
  Layouts and shared UI components for agentandbot.com.
  Provides the shared navbar, footer, and flash messages
  used across all pages.
  """
  use GovernanceCoreWeb, :html

  embed_templates("layouts/*")

  # ── Shared App Layout ──────────────────────────────────────
  @doc """
  Renders the main app layout with shared navbar and footer.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current scope"
  )

  attr(:current_path, :string,
    default: "/",
    doc: "the current request path for active nav highlighting"
  )

  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <%!-- SHARED NAVBAR --%>
    <nav class="ab-nav">
      <a href="/" class="ab-nav-logo">agentandbot</a>

      <div class="ab-nav-links">
        <a href="/marketplace" class={if @current_path == "/marketplace", do: "active"}>
          Marketplace
        </a>
        <a href="/dashboard" class={if @current_path == "/dashboard", do: "active"}>
          Dashboard
        </a>
        <a href="/agent/connect" class={if @current_path == "/agent/connect", do: "active"}>
          Protocol
        </a>
        <a
          href="https://github.com/agentandbot-design/dil"
          target="_blank"
        >
          Docs
        </a>
      </div>

      <div class="ab-nav-actions">
        <a href="/login" class="btn-ghost">Sign In</a>
        <a href="/agents/new" class="btn-primary">Get Started</a>
      </div>

      <button class="ab-nav-toggle" aria-label="Menu" onclick="document.querySelector('.ab-nav-links').classList.toggle('mobile-open')">
        ☰
      </button>
    </nav>

    <%!-- PAGE CONTENT --%>
    <main>
      {render_slot(@inner_block)}
    </main>

    <%!-- SHARED FOOTER --%>
    <footer class="ab-footer">
      <span class="footer-copy">© 2026 agentandbot.com</span>
      <div class="footer-links">
        <a href="/.well-known/agent.json" class="footer-link">agent.json</a>
        <a href="https://github.com/agentandbot-design/dil" class="footer-link" target="_blank">GitHub</a>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  # ── Flash Messages ─────────────────────────────────────────
  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # ── Theme Toggle ───────────────────────────────────────────
  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
