defmodule UcxChatWeb.MessageService do
  use UcxChatWeb, :service

  import Ecto.Query

  alias Ecto.Multi

  alias UcxChat.{
    Message, Repo, TypingAgent, User, Mention, Subscription, AppConfig,
    Settings, MessageView, ChatDat, Channel, ChannelService, UserChannel,
    SubscriptionService, MessageAgent, AttachmentService
  }
  alias UcxChat.ServiceHelpers, as: Helpers

  require UcxChat.ChatConstants, as: CC
  require Logger

  @preloads [:user, :edited_by, :attachments, :reactions]

  def preloads, do: @preloads

  def delete_message(%{attachments: attachments} = message) when is_list(attachments) do
    multi =
      Multi.new
      |> Multi.delete(:message, message)
      |> Multi.run(:attachments, &delete_attachments(&1, message.attachments))
    Repo.transaction(multi)
    |> case do
      {:ok, _} -> {:ok, message}
      error -> error
    end
  end

  def delete_message(message) do
    message
    |> Repo.preload([:attachments])
    |> delete_message
  end

  defp delete_attachments(_, attachments) do
    Enum.map(attachments, fn attachment ->
      AttachmentService.delete_attachment attachment
    end)
    |> Enum.any?(&(elem(&1, 0) == :error))
    |> case do
      true -> {:error, :attachment}
      _ -> {:ok, :attachment}
    end
  end

  def broadcast_updated_message(message, _opts \\ []) do
    message = Helpers.get Message, message.id, preload: @preloads
    channel = Helpers.get Channel, message.channel_id
    html =
      message
      |> Repo.preload(@preloads)
      |> render_message
    broadcast_message message.id, channel.name, message.user_id, html, event: "update"
    # event = if opts[:reaction], do: "code:update:reaction", else: "code:update"
    # UcxChat.Endpoint.broadcast! CC.chan_room <> channel.name, "code:update:reaction",
    #   %{selector: "##{message.id}", html: html, action: "replaceWith"}

  end

  def broadcast_bot_message(%{} = channel, _user_id, body) do
    Logger.warn "broadcast_bot_message body: #{inspect body}"
    bot_id = Helpers.get_bot_id()
    message = create_message(String.replace(body, "\n", "<br>"), bot_id, channel.id,
      %{
        # type: "p",
        system: true,
        sequential: false,
      })
    html = render_message message
    resp = create_broadcast_message(message.id, channel.name, html)
    UcxChat.Endpoint.broadcast! CC.chan_room <> channel.name, "message:new", resp
  end

  def broadcast_system_message(%{} = channel, _user_id, body) do
    message = create_system_message(channel.id, body)
    html = render_message message
    resp = create_broadcast_message(message.id, channel.name, html)
    UcxChat.Endpoint.broadcast! CC.chan_room <> channel.name, "message:new", resp
  end
  def broadcast_system_message(channel_id, user_id, body) do
    Channel
    |> Helpers.get(channel_id)
    |> broadcast_system_message(user_id, body)
  end

  def broadcast_message(id, room, user_id, html, opts \\ []) #event \\ "new")
  def broadcast_message(%{} = socket, id, user_id, html, opts) do
    event = opts[:event] || "new"
    Phoenix.Channel.broadcast! socket, "message:" <> event, create_broadcast_message(id, user_id, html, opts)
  end
  def broadcast_message(id, room, user_id, html, opts) do
    event = opts[:event] || "new"
    UcxChat.Endpoint.broadcast! CC.chan_room <> room, "message:" <> event, create_broadcast_message(id, user_id, html, opts)
  end

  def push_message(socket, id, user_id, html, opts \\ []) do
    Phoenix.Channel.push socket, "message:new", create_broadcast_message(id, user_id, html, opts)
  end

  defp create_broadcast_message(id, user_id, html, opts \\ []) do
    Enum.into opts,
      %{
        html: html,
        id: id,
        user_id: user_id
      }
  end

  def get_surrounding_messages(channel_id, "", user) do
    get_messages channel_id, user
  end
  def get_surrounding_messages(channel_id, timestamp, %{tz_offset: tz} = user) do
    message = Repo.one from m in Message,
      where: m.timestamp == ^timestamp and m.channel_id == ^channel_id,
      preload: ^@preloads
    if message do
      before_q = from m in Message,
        where: m.inserted_at < ^(message.inserted_at) and m.channel_id == ^channel_id,
        order_by: [desc: :inserted_at],
        limit: 50,
        preload: ^@preloads
      after_q = from m in Message,
        where: m.inserted_at > ^(message.inserted_at) and m.channel_id == ^channel_id,
        limit: 50,
        preload: ^@preloads

      Enum.reverse(Repo.all(before_q)) ++ [message|Repo.all(after_q)]
      |> new_days(tz || 0, [])
    else
      Logger.warn "did not find a message"
      get_messages(channel_id, user)
    end
  end

  def get_messages(channel_id, %{tz_offset: tz}) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> Helpers.last_page
    |> preload(^@preloads)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all
    |> new_days(tz || 0, [])
  end

  def get_room_messages(channel_id, %{id: user_id} = user) do
    page_size = AppConfig.page_size()
    case SubscriptionService.get(channel_id, user_id) do
      %{current_message: ""} -> nil
      %{current_message: cm} ->
        cnt1 = Repo.one from m in Message,
          where: m.channel_id == ^channel_id and m.timestamp >= ^cm,
          select: count(m.id)
        if cnt1 > page_size, do: cm, else: nil
      _ -> nil
    end
    |> case do
      nil ->
        get_messages(channel_id, user)
      ts ->
        get_messsages_ge_ts(channel_id, user, ts)
    end
  end

  def get_messsages_ge_ts(channel_id, %{tz_offset: tz}, ts) do
    before_q = from m in Message,
      where: m.timestamp < ^ts,
      order_by: [desc: :inserted_at],
      limit: 25,
      preload: ^@preloads

    after_q = from m in Message,
      where: m.channel_id == ^channel_id and m.timestamp >= ^ts,
      preload: ^@preloads

    Enum.reverse(Repo.all before_q) ++ Repo.all(after_q)
    |> new_days(tz || 0, [])
  end

  def get_messages_info(messages, channel_id, user) do
    subscription = SubscriptionService.get(channel_id, user.id)
    has_more =
      with [first|_] <- messages,
           _ <- Logger.warn("get_messages_info 2"),
           first_msg when not is_nil(first_msg) <- first_message(channel_id) do
        first.id != first_msg.id
      else
        _res -> false
      end
      has_more_next =
        with last when not is_nil(last) <- List.last(messages),
             last_msg when not is_nil(last_msg) <- last_message(channel_id) do
          last.id != last_msg.id
        else
          _res -> false
        end
    %{
      has_more: has_more, has_more_next: has_more_next, can_preview: true, last_read: Map.get(subscription || %{}, :last_read, "")
    }
  end

  def messages_info_into(messages, channel_id, user, params) do
    messages |> get_messages_info(channel_id, user) |> Enum.into(params)
  end

  defp new_days([h|t], tz, []), do: new_days(t, tz, [Map.put(h, :new_day, true)])
  defp new_days([h|t], tz, [last|_] = acc) do
    dt1 = Timex.shift(h.inserted_at, hours: tz)
    dt2 = Timex.shift(last.inserted_at, hours: tz)
    h = if Timex.day(dt1) == Timex.day(dt2) do
      h
    else
      Map.put(h, :new_day, true)
    end
    new_days t, tz, [h|acc]
  end
  defp new_days([], _, []), do: []
  defp new_days([], _, acc), do: Enum.reverse(acc)

  def last_user_id(channel_id) do
    channel_id
    |> last_message
    |> case do
      nil -> nil
      message -> Map.get(message, :user_id)
    end
  end

  def last_message(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> order_by([m], asc: m.inserted_at)
    |> last
    |> Repo.one
  end

  def first_message(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> order_by([m], asc: m.inserted_at)
    |> first
    |> Repo.one
  end

  def render_message(message) do
    user_id = message.user.id
    user = Repo.one(from u in User, where: u.id == ^user_id)
    "message.html"
    |> UcxChat.MessageView.render(message: message, user: user, previews: [])
    |> Helpers.safe_to_string
  end

  def create_system_message(channel_id, body) do
    bot_id = Helpers.get_bot_id()
    create_message(body, bot_id, channel_id,
      %{
        type: "p",
        system: true,
        sequential: false,
      })
  end

  def create_message(body, user_id, channel_id, params \\ %{}) do

    sequential? = case last_message(channel_id) do
      nil -> false
      lm ->
        Timex.after?(Timex.shift(lm.inserted_at,
          seconds: Settings.grouping_period_seconds()), Timex.now) and
          user_id == lm.user_id
    end

    message =
      %Message{}
      |> Message.changeset(Map.merge(
        %{
          sequential: sequential?,
          channel_id: channel_id,
          user_id: user_id,
          body: body
        }, params))
      |> Repo.insert!
      |> Repo.preload(@preloads)

    if params[:type] == "p" do
      Repo.delete(message)
    else
      embed_link_previews(body, channel_id, message.id)
    end
    message
  end

  def embed_link_previews(body, channel_id, message_id) do
    if Settings.embed_link_previews() do
      body
      |> get_preview_links
      |> case do
        [] -> :ok
        list ->
          do_embed_link_previews(list, channel_id, message_id)
      end
    end
  end

  def get_preview_links(nil), do: []
  def get_preview_links(body) do
    ~r/https?:\/\/[^\s]+/
    |> Regex.scan(body)
    |> List.flatten
  end

  def do_embed_link_previews(list, channel_id, message_id) do
    room = Repo.one from c in Channel,
            where: c.id == ^channel_id,
            select: c.name

    Enum.each(list, fn url ->
      spawn fn ->
        case MessageAgent.get_preview url do
          nil ->
            html = MessageAgent.put_preview url, create_link_preview(url, message_id)
            broadcast_link_preview(html, room, message_id)
          html ->
            spawn fn ->
              :timer.sleep(100)
              broadcast_link_preview(html, room, message_id)
            end
        end
      end
    end)
  end

  defp create_link_preview(url, _message_id) do
    case LinkPreview.create url do
      {:ok, page} ->
        img =
          case Enum.find(page.images, &String.match?(&1[:url], ~r/https?:\/\//)) do
            %{url: url} -> url
            _ -> nil
          end

        "link_preview.html"
        |> MessageView.render(page: struct(page, images: img))
        |> Helpers.safe_to_string

      _ -> ""
    end
  end

  defp broadcast_link_preview(nil, _room, _message_id) do
    nil
  end
  defp broadcast_link_preview(html, room, message_id) do
    # Logger.warn "broadcasting a preview: room: #{inspect room}, message_id: #{inspect message_id}, html: #{inspect html}"
    UcxChat.Endpoint.broadcast! CC.chan_room <> room, "message:preview",
      %{html: html, message_id: message_id}
  end

  def message_previews(user_id, messages) when is_list(messages) do
    Enum.reduce messages, [], fn message, acc ->
      case get_preview_links(message.body) do
        [] -> acc
        list ->
          html_list = get_preview_html(list)
          for {url, html} <- html_list, is_nil(html) do
            spawn fn ->
              html = MessageAgent.put_preview url, create_link_preview(url, message.id)
              UcxChat.Endpoint.broadcast!(CC.chan_user <> user_id, "message:preview",
                %{html: html, message_id: message.id})
            end
          end
          [{message.id, html_list} | acc]
      end
    end
  end

  defp get_preview_html(list) do
    Enum.map list, &({&1, MessageAgent.get_preview(&1)})
  end

  def stop_typing(socket, user_id, channel_id) do
    TypingAgent.stop_typing(channel_id, user_id)
    update_typing(socket, channel_id)
  end

  def update_typing(%{} = socket, channel_id) do
    typing = TypingAgent.get_typing_names(channel_id)
    Phoenix.Channel.broadcast! socket, "typing:update", %{typing: typing}
  end

  def update_typing(channel_id, room) do
    typing = TypingAgent.get_typing_names(channel_id)
    UcxChat.Endpoint.broadcast(CC.chan_room <> room, "typing:update", %{typing: typing})
  end

  def encode_mentions(body, channel_id) do
    body
    |> encode_user_mentions(channel_id)
    |> encode_channel_mentions
  end

  def encode_channel_mentions({body, acc}) do
    re = ~r/(^|\s|\!|:|,|\?)#([\.a-zA-Z0-9_-]*)/
    body = if (list = Regex.scan(re, body)) != [] do
      Enum.reduce(list, body, fn [_, _, name], body ->
        encode_channel_mention(name, body)
      end)
    else
      body
    end
    {body, acc}
  end

  def encode_channel_mention(name, body) do
    Channel
    |> where([c], c.name == ^name)
    |> Repo.one
    |> do_encode_channel_mention(name, body)
  end

  def do_encode_channel_mention(nil, _, body), do: body
  def do_encode_channel_mention(_channel, name, body) do
    name_link = " <a class='mention-link' data-channel='#{name}'>##{name}</a> "
    String.replace body, ~r/(^|\s|\.|\!|:|,|\?)##{name}[\.\!\?\,\:\s]*/, name_link
  end

  def encode_user_mentions(body, channel_id) do
    re = ~r/(^|\s|\!|:|,|\?)@([\.a-zA-Z0-9_-]*)/
    if (list = Regex.scan(re, body)) != [] do
      Enum.reduce(list, {body, []}, fn [_, _, name], {body, acc} ->
        encode_user_mention(name, body, channel_id, acc)
      end)
    else
      {body, []}
    end
  end

  def encode_user_mention(name, body, channel_id, acc) do
    User
    |> where([c], c.username == ^name)
    |> Repo.one
    |> do_encode_user_mention(name, body, channel_id, acc)
  end

  def do_encode_user_mention(nil, name, body, _, acc) when name in ~w(all here) do
    name_link =
      " <a class='mention-link mention-link-me mention-link-#{name} background-attention-color' >@#{name}</a> "
    body = String.replace body, ~r/(^|\s|\.|\!|:|,|\?)@#{name}[\.\!\?\,\:\s]*/, name_link
    {body, [{nil, name}|acc]}
  end
  def do_encode_user_mention(nil, _, body, _, acc), do: {body, acc}
  def do_encode_user_mention(user, name, body, _channel_id, acc) do
    name_link = " <a class='mention-link' data-username='#{user.username}'>@#{name}</a> "
    body = String.replace body, ~r/(^|\s|\.|\!|:|,|\?)@#{name}[\.\!\?\,\:\s]*/, name_link
    {body, [{user.id, name}|acc]}
  end

  def create_mentions([], _, _, _), do: :ok
  def create_mentions([mention|mentions], message_id, channel_id, body) do
    create_mention(mention, message_id, channel_id, body)
    create_mentions(mentions, message_id, channel_id, body)
  end

  def create_mention({nil, _}, _, _, _), do: nil
  def create_mention({mention, name}, message_id, channel_id, body) do
    {all, nm} = if name in ~w(all here), do: {true, name}, else: {false, nil}
    %Mention{}
    |> Mention.changeset(%{user_id: mention, all: all, name: nm, message_id: message_id, channel_id: channel_id})
    |> Repo.insert!
    |> UserChannel.notify_mention(body)

    subs =
      Subscription
      |> where([s], s.user_id == ^mention and s.channel_id == ^channel_id)
      |> Repo.one
      |> case do
        nil ->
          {:ok, subs} = ChannelService.join_channel(channel_id, mention)
          subs
        subs ->
          subs
      end

    subs
    |> Subscription.changeset(%{unread: subs.unread + 1})
    |> Repo.update!
  end

  def update_direct_notices(%{type: 2, id: id}, %{user_id: user_id}) do
    Subscription
    |> where([s], s.channel_id == ^id and s.user_id != ^user_id)
    |> Repo.all
    |> Enum.each(fn %{unread: unread} = sub ->
      sub
      |> Subscription.changeset(%{unread: unread + 1})
      |> Repo.update!
    end)
  end
  def update_direct_notices(_channel, _message), do: nil

  def create_and_render(body, user_id, channel_id, opts \\ []) do
    message = create_message(body, user_id, channel_id, Enum.into(opts, %{}))
    {message, render_message(message)}
  end

  def render_message_box(channel_id, user_id) do
    user = Helpers.get_user! user_id
    channel = case Helpers.get(Channel, channel_id) do
      nil ->
        Channel
        |> first
        |> Repo.one
      channel ->
        channel
    end
    chatd = ChatDat.new(user, channel)
    MessageView.render("message_box.html", chatd: chatd, mb: MessageView.get_mb(chatd))
    |> Helpers.safe_to_string
  end
end
