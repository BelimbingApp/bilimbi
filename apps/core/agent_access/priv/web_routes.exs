[
  %{path: "/oauth/authorize", live: Bilimbi.Core.AgentAccess.Web.AuthorizeLive, session: :auth},
  %{path: "/oauth/device", live: Bilimbi.Core.AgentAccess.Web.DeviceLive, session: :auth},
  %{
    path: "/settings/agent-connections",
    live: Bilimbi.Core.AgentAccess.Web.ConnectionsLive,
    session: :auth
  }
]
