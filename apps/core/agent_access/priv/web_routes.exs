[
  %{
    path: "/settings/chatgpt-plugin",
    live: Bilimbi.Core.AgentAccess.Web.PluginLive,
    session: :auth
  },
  %{
    path: "/settings/chatgpt-plugin/download",
    controller: Bilimbi.Core.AgentAccess.Web.PluginController,
    action: :download,
    session: :auth
  },
  %{path: "/oauth/authorize", live: Bilimbi.Core.AgentAccess.Web.AuthorizeLive, session: :auth},
  %{path: "/oauth/device", live: Bilimbi.Core.AgentAccess.Web.DeviceLive, session: :auth},
  %{
    path: "/settings/agent-connections",
    live: Bilimbi.Core.AgentAccess.Web.ConnectionsLive,
    session: :auth
  }
]
