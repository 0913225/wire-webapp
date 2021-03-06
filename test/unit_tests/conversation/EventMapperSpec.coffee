#
# Wire
# Copyright (C) 2016 Wire Swiss GmbH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see http://www.gnu.org/licenses/.
#

# grunt test_init && grunt test_run:conversation/EventMapper

describe 'Event Mapper', ->
  conversation_et = null
  event_mapper = null

  beforeAll (done) ->
    z.util.protobuf.load_protos 'ext/proto/generic-message-proto/messages.proto'
    .then -> done()

  beforeEach ->
    conversation_et = new z.entity.Conversation z.util.create_random_uuid()
    event_mapper = new z.conversation.EventMapper()

  describe 'map_json_event', ->
    it 'maps text messages without link previews', ->
      event_id = z.util.create_random_uuid

      event =
        conversation: conversation_et.id
        data:
          content: 'foo'
          nonce: event_id
        id: event_id
        from: z.util.create_random_uuid
        time: Date.now()
        type: z.event.Backend.CONVERSATION.MESSAGE_ADD

      message_et = event_mapper.map_json_event event, conversation_et
      expect(message_et.get_first_asset().text).toBe 'foo'
      expect(message_et).toBeDefined()

    it 'maps text messages with link previews', ->
      event_id = z.util.create_random_uuid

      article = new z.proto.Article 'test.com', 'Test title', 'Test description'
      link_preview = new z.proto.LinkPreview 'test.com', 0, article

      event =
        conversation: conversation_et.id
        data:
          content: 'test.com'
          nonce: event_id
          previews: [link_preview.encode64()]
        id: event_id
        from: z.util.create_random_uuid
        time: Date.now()
        type: z.event.Backend.CONVERSATION.MESSAGE_ADD

      message_et = event_mapper.map_json_event event, conversation_et
      expect(message_et.get_first_asset().text).toBe 'test.com'
      expect(message_et.get_first_asset().previews().length).toBe 1
      expect(message_et.get_first_asset().previews()[0].original_url).toBe 'test.com'
      expect(message_et).toBeDefined()

    it 'maps text messages with unsupported link previews', ->
      event_id = z.util.create_random_uuid

      twitter_status = new z.proto.TwitterStatus 'test.com'
      link_preview = new z.proto.LinkPreview 'test.com', 0, null, twitter_status

      event =
        conversation: conversation_et.id
        data:
          content: 'test.com'
          nonce: event_id
          previews: [link_preview.encode64()]
        id: event_id
        from: z.util.create_random_uuid
        time: Date.now()
        type: z.event.Backend.CONVERSATION.MESSAGE_ADD

      message_et = event_mapper.map_json_event event, conversation_et
      expect(message_et.get_first_asset().text).toBe 'test.com'
      expect(message_et.get_first_asset().previews().length).toBe 0
      expect(message_et).toBeDefined()

    it 'skips messages which cannot be mapped', ->
      # @formatter:off
      good_message = {"conversation":conversation_et.id,"id":"4cec0f75-d963-486d-9401-415240ac2ad8","from":"532af01e-1e24-4366-aacf-33b67d4ee376","time":"2016-08-04T15:12:12.453Z","data":{"content":"Message with timestamp","nonce":"4cec0f75-d963-486d-9401-415240ac2ad8","previews":[]},"type":"conversation.message-add"}
      bad_message = {"conversation":conversation_et.id,"id":"aeac8355-739b-4dfc-a119-891a52c6a8dc","from":"532af01e-1e24-4366-aacf-33b67d4ee376","data":{"content":"Knock, are you there? :)","nonce":"aeac8355-739b-4dfc-a119-891a52c6a8dc"},"type":"conversation.message-add"}
      # @formatter:on

      message_ets = event_mapper.map_json_events events: [good_message, bad_message], conversation_et
      expect(message_ets.length).toBe 1
