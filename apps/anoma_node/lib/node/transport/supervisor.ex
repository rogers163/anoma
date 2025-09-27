defmodule Anoma.Node.Transport.Supervisor do
  @moduledoc """
  I am the transport supervisor.

  My main functionality is to supervise the physical transport connections
  in this node (e.g., TCP connections).
  """

  use Supervisor

  alias Anoma.Node.Registry
  alias Anoma.Node.Transport
  alias Anoma.Node.Transport.NetworkRegister

  require Logger

  @spec start_link([any()]) :: GenServer.on_start()
  def start_link(args) do
    args = Keyword.validate!(args, [:node_id, :node_config])
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  @doc """
  I initialize a new transport supervision tree.

  ### Options

  - `:node_id` - The key of the local node.
  """
  def init(args) do
    Logger.debug("starting transport supervisor #{inspect(args)}")
    Process.set_label(__MODULE__)

    # validate args and set defaults
    args = Keyword.validate!(args, [:node_id, :node_config])
    node_id = args[:node_id]
    node_config = args[:node_config]
    
    # 从node_config获取gRPC端口，如果没有则使用默认值
    grpc_port = Map.get(node_config, :grpc_port, 50051)

    # 为每个节点的gRPC服务器创建唯一名称
    grpc_server_name = Registry.via(node_id, Transport.GRPCServerSupervisor)
    
    children = [
      {DynamicSupervisor,
       name: Registry.via(node_id, Transport.ProxySupervisor)},
      {NetworkRegister, [node_id: node_id, node_config: node_config]},
      # 为每个节点启动独立的gRPC服务器，使用唯一名称和端口
      # 使用自定义适配器支持自定义监听器名称来避免冲突
      Supervisor.child_spec(
        {GRPC.Server.Supervisor, [
          servers: [
            Anoma.Node.Transport.GRPC.Servers.Intents,
            Anoma.Node.Transport.GRPC.Servers.Mempool,
            Anoma.Node.Transport.GRPC.Servers.Executor,
            Anoma.Node.Transport.GRPC.Servers.Advertisement,
            Anoma.Node.Transport.GRPC.Servers.IntraNode,
            Anoma.Node.Transport.GRPC.Servers.PubSub
          ],
          port: grpc_port, 
          start_server: true,
          adapter: Anoma.Node.Transport.GRPC.CustomCowboyAdapter,
          adapter_opts: [listener_name: grpc_server_name]
        ]},
        id: grpc_server_name
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
