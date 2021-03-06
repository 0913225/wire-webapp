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

window.z ?= {}
z.storage ?= {}

###
Base class for persistent storage.
###
class z.storage.StorageService
  OBJECT_STORE_AMPLIFY: 'amplify'
  OBJECT_STORE_CLIENTS: 'clients'
  OBJECT_STORE_CONVERSATION_EVENTS: 'conversation_events'
  OBJECT_STORE_CONVERSATIONS: 'conversations'
  OBJECT_STORE_KEYS: 'keys'
  OBJECT_STORE_PREKEYS: 'prekeys'
  OBJECT_STORE_SESSIONS: 'sessions'

  constructor: ->
    @logger = new z.util.Logger 'z.storage.StorageService', z.config.LOGGER.OPTIONS

    @db = undefined
    @db_name = undefined
    @user_id = undefined

    return @

  ###############################################################################
  # Initialization
  ###############################################################################

  ###
  Initialize the IndexedDB for a user.

  @param user_id [String] User ID
  @return [Promise] Promise that will resolve with the database name
  ###
  init: (user_id = @user_id) =>
    return new Promise (resolve, reject) =>
      is_permanent = z.storage.get_value z.storage.StorageKey.AUTH.PERSIST
      client_type = if is_permanent then z.client.ClientType.PERMANENT else z.client.ClientType.TEMPORARY

      @user_id = user_id
      @db_name = "wire@#{z.util.Environment.backend.current}@#{user_id}@#{client_type}"

      # https://github.com/dfahlander/Dexie.js/wiki/Version.stores()
      version_1 =
        "#{@OBJECT_STORE_AMPLIFY}": ''
        "#{@OBJECT_STORE_CLIENTS}": ''
        "#{@OBJECT_STORE_CONVERSATION_EVENTS}": ', raw.conversation, raw.time, meta.timestamp'
        "#{@OBJECT_STORE_KEYS}": ''
        "#{@OBJECT_STORE_PREKEYS}": ''
        "#{@OBJECT_STORE_SESSIONS}": ''

      version_2 =
        "#{@OBJECT_STORE_AMPLIFY}": ''
        "#{@OBJECT_STORE_CLIENTS}": ''
        "#{@OBJECT_STORE_CONVERSATION_EVENTS}": ', raw.conversation, raw.time, raw.type, meta.timestamp'
        "#{@OBJECT_STORE_KEYS}": ''
        "#{@OBJECT_STORE_PREKEYS}": ''
        "#{@OBJECT_STORE_SESSIONS}": ''

      version_3 =
        "#{@OBJECT_STORE_AMPLIFY}": ''
        "#{@OBJECT_STORE_CLIENTS}": ''
        "#{@OBJECT_STORE_CONVERSATION_EVENTS}": ', raw.conversation, raw.time, raw.type, meta.timestamp'
        "#{@OBJECT_STORE_CONVERSATIONS}": ', id, last_event_timestamp'
        "#{@OBJECT_STORE_KEYS}": ''
        "#{@OBJECT_STORE_PREKEYS}": ''
        "#{@OBJECT_STORE_SESSIONS}": ''

      version_4 =
        "#{@OBJECT_STORE_AMPLIFY}": ''
        "#{@OBJECT_STORE_CLIENTS}": ', meta.primary_key'
        "#{@OBJECT_STORE_CONVERSATION_EVENTS}": ', raw.conversation, raw.time, raw.type, meta.timestamp'
        "#{@OBJECT_STORE_CONVERSATIONS}": ', id, last_event_timestamp'
        "#{@OBJECT_STORE_KEYS}": ''
        "#{@OBJECT_STORE_PREKEYS}": ''
        "#{@OBJECT_STORE_SESSIONS}": ''

      @db = new Dexie @db_name

      @db.on 'blocked', =>
        @logger.log @logger.levels.ERROR, 'Database is blocked'

      # @see https://github.com/dfahlander/Dexie.js/issues/189#issuecomment-196304545
      # @see https://github.com/dfahlander/Dexie.js/wiki/Dexie.UpgradeError
      Dexie.Promise.on 'error', (error) =>
        switch error.name
          when Dexie.errnames.Upgrade
            @logger.log @logger.levels.ERROR, "Failed to open database '#{@db_name}': #{error.message}", error
          else
            @logger.log @logger.levels.ERROR, "Database error (#{error.name}): #{error.message}", error

      # @see https://github.com/dfahlander/Dexie.js/wiki/Version.upgrade()
      # @see https://github.com/dfahlander/Dexie.js/wiki/WriteableCollection.modify()
      @db.version(1).stores version_1
      @db.version(2).stores version_2
      @db.version(3).stores version_3
      @db.version(4).stores version_4
      .upgrade (transaction) =>
        @logger.log @logger.levels.WARN, 'Database upgrade to version 4', transaction
        transaction[@OBJECT_STORE_CLIENTS].toCollection().modify (client) =>
          client.meta =
            is_verified: true
            primary_key: 'local_identity'
          @logger.log 'Updated client', client
      @db.version(5).stores version_4
      @db.version(6).stores version_4
      .upgrade (transaction) =>
        @logger.log @logger.levels.WARN, 'Database upgrade to version 6', transaction
        transaction[@OBJECT_STORE_CONVERSATIONS].toCollection().eachKey (key) =>
          @db[@OBJECT_STORE_CONVERSATIONS].update key, {id: key}
        transaction[@OBJECT_STORE_SESSIONS].toCollection().eachKey (key) =>
          @db[@OBJECT_STORE_SESSIONS].update key, {id: key}
        transaction[@OBJECT_STORE_PREKEYS].toCollection().eachKey (key) =>
          @db[@OBJECT_STORE_PREKEYS].update key, {id: key}

      @db.open()
      .then =>
        @logger.log @logger.levels.LEVEL_1, "Storage Service initialized with database '#{@db_name}'"
        resolve @db_name
      .catch (error) =>
        @logger.log @logger.levels.ERROR, "Failed to initialize database '#{@db_name}' for Storage Service"
        reject error


  ###############################################################################
  # Interactions
  ###############################################################################

  ###
  Removes persisted data.

  @param store_name [String] Name of the object store
  @param primary_key [String] Primary key
  @return [Promise] Promise that will resolve when the object is deleted
  ###
  delete: (store_name, primary_key) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name].delete primary_key
        .then =>
          @logger.log "Deleted '#{primary_key}' from object store '#{store_name}'"
          resolve primary_key
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Failed to delete '#{primary_key}' from store '#{store_name}'", error
          reject error
      else
        reject new Error "Data store '#{store_name}' not found"

  clear_all_stores: =>
    promises = (@delete_store store_name for store_name of @db._dbSchema)
    return Promise.all promises

  ###
  @return [Promise]
  ###
  delete_store: (store_name) =>
    @logger.log "Clearing object store '#{store_name}' in database '#{@db_name}'"
    return @db[store_name].clear()

  ###
  Delete the IndexedDB with all its stores.
  @return [Promise] Promise that will resolve if a database is found and cleared
  ###
  delete_everything: =>
    return new Dexie.Promise (resolve, reject) =>
      if @db?
        @db.delete()
        .then =>
          @logger.log @logger.levels.INFO, "Clearing IndexedDB '#{@db_name}' successful"
          resolve true
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Clearing IndexedDB '#{@db_name}' failed"
          reject error
      else
        @logger.log @logger.levels.ERROR, "IndexedDB '#{@db_name}' not found"
        resolve true

  ###
  Returns an array of all records for a given object store.

  @param store_name [String] Name of object store
  @return [Promise] Promise that will resolve with the records from the object store
  ###
  get_all: (store_name) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name]
        .toArray()
        .then (records) -> resolve records
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Could not load objects from store '#{store_name}'", error
          reject error
      else
        reject new Error "Data store '#{store_name}' not found"

  ###
  Returns an array of all keys in a given object store.

  @param store_name [String] Name of object store
  @return [Promise] Promise that will resolve with the keys of the object store
  ###
  get_keys: (store_name, regex_string) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name]
        .toCollection()
        .keys()
        .then (keys) ->
          if regex_string is undefined
            resolve keys
          else
            regex = new RegExp regex_string, 'igm'
            accepted_keys = keys.filter (key) -> key.match regex
            resolve accepted_keys
        .catch (error) -> reject error
      else
        reject new Error "Data store '#{store_name}' not found"

  ###
  Loads persisted data via a promise.

  @note If a key cannot be found, it resolves and returns "undefined".

  @param store_name [String] Name of object store
  @param primary_key [String] Primary key of object to be retrieved
  @return [Promise] Promise that will resolve with the record matching the primary key
  ###
  load: (store_name, primary_key) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name].get primary_key
        .then (record) -> resolve record
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Failed to load '#{primary_key}' from store '#{store_name}'", error
          reject error
      else
        reject new Error "Data store '#{store_name}' not found"

  ###
  Loads all objects from an object store and returns them with their keys and values.

  @example Return value:
    {
      "key_1": {
        "property_1": value_1,
        "property_2": value_2
      },
      "key_2": {
        "property_1": value_1,
        "property_2": value_2
      },
      ...
    }

  @param store_name [String] Name of object store
  @return [Promise<Object[String, Object]>] Promise which resolves with an object containing all keys and values
  ###
  load_all: (store_name, regex_string) =>
    return new Dexie.Promise (resolve, reject) =>
      data = {}

      @get_keys store_name, regex_string
      .then (keys) =>
        promises = keys.map (key) =>
          return new Promise (resolve, reject) =>
            @load store_name, key
            .then (value) ->
              data[key] = value
              resolve undefined
            .catch (error) -> reject error
        return Promise.all promises
      .then -> resolve data
      .catch (error) -> reject error

  ###
  Saves objects in the local database.

  @param store_name [String] Name of object store where to save the object
  @param primary_key [String] Primary key which should be used to store the object
  @return [Promise] Promise that will resolve with the primary key of the persisted object
  ###
  save: (store_name, primary_key, entity) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name].put entity, primary_key
        .then (key) -> resolve key
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Failed to put '#{primary_key}' into store '#{store_name}'", error
          reject error
      else
        reject new Error "Data store '#{store_name}' not found"

  ###
  Closes the database. This operation completes immediately and there is no returned Promise.
  @see https://github.com/dfahlander/Dexie.js/wiki/Dexie.close()
  ###
  terminate: ->
    @logger.log "Closing database connection with '#{@db.name}'"
    @db.close()

  ###
  Update previously persisted data via a promise.

  @param store_name [String] Name of object store
  @param primary_key [String] Primary key of object to be updated
  @param changes [Object] Object containing the key paths to each property you want to change
  @return [Promise] Promise with the number of updated records (1 if an object was updated, otherwise 0).
  ###
  update: (store_name, primary_key, changes) =>
    return new Dexie.Promise (resolve, reject) =>
      if @db[store_name]?
        @db[store_name].update primary_key, changes
        .then (number_of_updates) =>
          @logger.log @logger.levels.INFO,
            "Updated #{number_of_updates} record(s) with key '#{primary_key}' in store '#{store_name}'", changes
          resolve number_of_updates
        .catch (error) =>
          @logger.log @logger.levels.ERROR, "Failed to update '#{primary_key}' in store '#{store_name}'", error
          reject error
      else
        reject new Error "Data store '#{store_name}' not found"
