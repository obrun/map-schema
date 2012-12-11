--[[ $%BEGINLICENSE%$

LICENSE:
 Copyright 2012 SwarmPoint LLC. Provided by SwarmPoint LLC as is and without warranty.
 License granted for internal commercial or private use, modification or translation.
 Distribution only under the same license. No right to use to offer a database service.
 Owen Brunette owen@beliefs.com +1-646-461-4401 owenbrunette.com

 $%ENDLICENSE%$ --]]

--[[ 
 Execute with the start script or in another way achieve:

 LD_LIBRARY_PATH needs to include the location of your mysql-proxy lib directory
 REPLACE my_model_schema WITH THE NAME OF YOUR MODEL SCHEMA

 MAP_SCHEMA_MODEL=my_model_schema
 $HOME/bin/mysql-proxy --proxy-lua-script=${HOME}/local/map-schema/map-schema.lua

 or at a different location where you installed mysql-proxy and this script.
--]]

-- server_capabilities added at mysql-proxy 0.8.3
-- network_mysqld_auth_response_new capability flags
local CLIENT_LONG_PASSWORD     = 1      -- new more secure passwords
local CLIENT_FOUND_ROWS        = 2      -- Found instead of affected rows
local CLIENT_LONG_FLAG         = 4      -- Get all column flags
local CLIENT_CONNECT_WITH_DB   = 8      -- One can specify db on connect
local CLIENT_NO_SCHEMA         = 16     -- Don't allow database.table.column
local CLIENT_COMPRESS          = 32     -- Can use compression protocol
local CLIENT_ODBC              = 64     -- Odbc client
local CLIENT_LOCAL_FILES       = 128    -- Can use LOAD DATA LOCAL
local CLIENT_IGNORE_SPACE      = 256    -- Ignore spaces before '('
local CLIENT_PROTOCOL_41       = 512    -- New 4.1 protocol
local CLIENT_INTERACTIVE       = 1024   -- This is an interactive client
local CLIENT_SSL               = 2048   -- Switch to SSL after handshake
local CLIENT_IGNORE_SIGPIPE    = 4096   -- IGNORE sigpipes
local CLIENT_TRANSACTIONS      = 8192   -- Client knows about transactions
local CLIENT_RESERVED          = 16384  -- Old flag for 4.1 protocol
local CLIENT_SECURE_CONNECTION = 32768  -- New 4.1 authentication
local CLIENT_MULTI_STATEMENTS  = 65536  -- Enable/disable multi-stmt support
local CLIENT_MULTI_RESULTS     = 131072 -- Enable/disable multi-results
local CLIENT_PS_MULTI_RESULTS  = 262144 -- Multi-results in PS-protocol
local CLIENT_PLUGIN_AUTH       = 524288 -- Client supports plugin authentication

local MYSQL_AUTH_CAPABILITIES  = ( CLIENT_PROTOCOL_41 + CLIENT_SECURE_CONNECTION
--                                + CLIENT_LONG_PASSWORD + CLIENT_LONG_FLAG + CLIENT_TRANSACTIONS
--                                + CLIENT_MULTI_RESULTS + CLIENT_PS_MULTI_RESULTS
--                                + CLIENT_LOCAL_FILES + CLIENT_PLUGIN_AUTH
                                 )
                                 -- '+' is substituting for a bitwise OR here

local proto = assert(require("mysql.proto"))

-- proxy.global is shared between connections.
--[[
-- You may define a fuller set of mappings here for
-- multiple users by removing the --[[ comment marks
-- This is optional. By default the default_db value from
-- the workbench connection profile should be the physical table
-- and proxy.global.config.map_schema_default should be the model schema
-- This is optional. By default the default_db value from
-- the workbench connection profile should be the physical table
-- and proxy.global.config.map_schema_default should be the model schema

proxy.global.config.map_schema = {
        [ 'a_mysql_user_name' ] = {
            server_schema = 'the_physical_schema',
            client_schema = 'the_models_schema'
        },
        [ 'another_mysql_user_name' ] = {
            server_schema = 'the_physical_schema',
            client_schema = 'the_models_schema'
        },
    }
--]]

if not proxy.global.config.map_schema then
    proxy.global.config.map_schema = {
	    {}
    }
end
if not proxy.global.config.map_schema_is_debug then
    proxy.global.config.map_schema_is_debug = false
end
-- Default name of the schema used within the workbench model
if not proxy.global.config.map_schema_default then
    proxy.global.config.map_schema_default = os.getenv("MAP_SCHEMA_MODEL")
end

function read_auth()
	local c = proxy.connection.client
	local s = proxy.connection.server
    local is_debug = proxy.global.config.map_schema_is_debug

    print("NEW CONNECTION:------------------------------------------------------")
    print("read_auth:Login for: " .. c.username .. " from " .. c.src.name .. ".")
    -- proxy.global.backends.connected_clients


    print("read_auth:schema was: " .. c.default_db .. ".")
	local mapped = proxy.global.config.map_schema[c.username]
    if not mapped then
        -- if c.default_db ~= 'information_schema' then
            -- print("read_auth:Creating the map and setting the >>>server target schema to be: " .. c.default_db .. "<<<" )
            -- proxy.global.config.map_schema[c.username] = { server_schema = c.default_db } -- The schema name used by the mysql server -- Mapped a reference to global
            proxy.global.config.map_schema[c.username] = {  } -- Mapped is a reference to global
            mapped = proxy.global.config.map_schema[c.username]
        -- end
    end
	if mapped then
        local schema = c.default_db
        if not mapped.server_schema and schema ~= 'information_schema' then
            print("read_auth:Setting the >>>server target schema to be: " .. c.default_db .. "<<<" )
            mapped['server_schema'] = schema -- The target schema name used by the mysql server -- Mapped is a reference to global
        end
        -- If we are changing what the connection asked for then announce this.
        if mapped.server_schema and schema ~= mapped.server_schema then
            print("read_auth:schema was: " .. c.default_db .. " but replacing with " .. schema .. ".")
            schema = mapped.server_schema
        end
        -- proxy.PROXY_VERSION >= 0x00803 needs server_capabilities
		proxy.queries:append(1,  -- id to be used in read_query_result
			proto.to_response_packet({
				username = c.username,
				response = c.scrambled_password,
  				database = schema,
				charset  = 8, -- default charset
				max_packet_size = 1 * 1024 * 1024,
                server_capabilities = MYSQL_AUTH_CAPABILITIES; -- added at mysql-proxy 0.8.3
			})
		)
		return proxy.PROXY_SEND_QUERY
	end
end


function read_query( packet )

    local is_debug = proxy.global.config.map_schema_is_debug

    -- Identify our special queries and put them on the queue so that reqd_query_result is called.
    if packet:byte() == proxy.COM_QUERY then
        print("read_query:normal query: " .. packet:sub(2) )

        -- try to match the string up to the first non-alphanum
        local f_s, f_e, command = string.find(packet, "^%s*(%w+)", 2)
        local option

        if is_debug then
            print("read_query:command: " .. command .. " as " .. string.lower(command) )
        end
        if f_e then
            -- if that match, take the next sub-string as option
            f_s, f_e, option = string.find(packet, "^%s+(%w+)", f_e + 1)

            if option then
                print("read_query:type: " .. type(option) .. " option: " .. option )
            end
        end
        -- USE `server_schema`
        if string.lower(command) == "use"
                then
            local schema = string.lower(string.sub(packet:sub(2),6,#packet:sub(2) - 1))
            if is_debug then
                print("read_query:schema: " .. schema )
            end
	        local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
            if is_debug then
                print("read_query:username: " .. proxy.connection.client.username .. " as " .. tostring(mapped) )
            end
	        if mapped then
                if mapped.client_schema then
                    if is_debug then
                        print("read_query:client_schema: " .. mapped.client_schema )
                    end
                    if schema == mapped.client_schema then
                        schema = mapped.server_schema
		                proxy.queries:append(2, string.char(proxy.COM_QUERY) .. "USE `" .. schema .. "`")
                        print("read_query:substituted: USE `" .. schema .. "`" )
                        return proxy.PROXY_SEND_QUERY
                    end
                else
                    if schema ~= mapped.server_schema then
                        print("Unable to map schema " .. schema .. ". Probably the default model schema was not set.")
                    end
                end
            end
        -- 3) SELECT 'schema' AS 'OBJECT_TYPE', CATALOG_NAME as 'CATALOG', SCHEMA_NAME as 'SCHEMA', SCHEMA_NAME as 'NAME' FROM information_schema.schemata
        elseif string.lower(command) == "select" then
            print("read_query:select packet: " .. packet:sub(2) )
            infoSchema = string.find (string.lower(packet:sub(2)), "information_schema.schemata")
            tableSchema = string.find (string.lower(packet:sub(2)), "information_schema.tables")
            viewSchema = string.find (string.lower(packet:sub(2)), "information_schema.views")
            routineSchema = string.find (string.lower(packet:sub(2)), "information_schema.routines")
            triggerSchema = string.find (string.lower(packet:sub(2)), "information_schema.triggers")
            if infoSchema then
		        proxy.queries:append(3, packet,
                    { resultset_is_needed = true } ) -- cause to be sent to read_query_result
                if is_debug then
                    print("read_query:put a hook in for select schema." )
                end
                return proxy.PROXY_SEND_QUERY
               
         -- 7) SELECT 'table' AS 'OBJECT_TYPE', TABLE_CATALOG as 'CATALOG', TABLE_SCHEMA as 'SCHEMA', TABLE_NAME as 'NAME' FROM information_schema.tables WHERE table_type<>'VIEW' AND table_schema = 'model_schema'
         -- 8) SELECT 'view' AS 'OBJECT_TYPE', TABLE_CATALOG as 'CATALOG', TABLE_SCHEMA as 'SCHEMA', TABLE_NAME as 'NAME' FROM information_schema.views WHERE table_schema = 'model_schema'
            elseif tableSchema or viewSchema then
                -- use lower case in the following as TABLE_SCHEMA preceeds table_schema
                tableSchema = string.find (packet:sub(2), "table_schema")
                packetAfter = string.sub(packet:sub(2),tableSchema,#packet:sub(2))
                openAfter = string.find ( packetAfter, "'" )
                if is_debug then
                    print("read_query:tableSchema/viewSchema " .. tableSchema )
                end
                if openAfter then
                    if is_debug then
                        print("read_query:The openAfter is at " .. openAfter )
                    end
                    openAfter = openAfter + tableSchema - 1
                    closeBefore = string.find ( string.sub(packet:sub(2),openAfter +1), "'" ) + openAfter
                    if is_debug then
                        print("read_query:The closeBefore is at " .. closeBefore )
                        print("read_query:The length is " .. (closeBefore - openAfter -1) )
                    end
                    schema = string.lower(string.sub(packet:sub(2),openAfter+1,closeBefore-1))
                    if is_debug then
                        print("read_query:schema: " .. schema )
                    end
	                local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
                    if mapped then
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
                            proxy.queries:append(7, string.char(proxy.COM_QUERY) .. string.sub(packet:sub(2),1,openAfter) .. schema .. string.sub(packet:sub(2),closeBefore), { resultset_is_needed = true } )
                            if is_debug then
                                print("read_query:substituted: schema `" .. schema .. "` in a table/viewSchema statement" )
                                print("read_query:put a hook in for select table / view." )
                            end
                            return proxy.PROXY_SEND_QUERY
                        end
                    end
                end

         -- 9) SELECT ROUTINE_TYPE AS 'OBJECT_TYPE', ROUTINE_CATALOG as 'CATALOG', ROUTINE_SCHEMA as 'SCHEMA', ROUTINE_NAME as 'NAME' FROM information_schema.routines WHERE routine_schema = 'model_schema'

            elseif routineSchema then
                print("read_query:found a routine schema." )
                -- use lower case in the following as ROUTINE_SCHEMA preceeds routine_schema
                routineSchema = string.find (packet:sub(2), "routine_schema")
                packetAfter = string.sub(packet:sub(2),routineSchema,#packet:sub(2))
                openAfter = string.find ( packetAfter, "'" )
                if openAfter then
                    if is_debug then
                        print("read_query:The openAfter is at " .. openAfter )
                    end
                    openAfter = openAfter + routineSchema - 1
                    closeBefore = string.find ( string.sub(packet:sub(2),openAfter +1), "'" ) + openAfter
                    if is_debug then
                        print("read_query:The closeBefore is at " .. closeBefore )
                        print("read_query:The length is " .. (closeBefore - openAfter -1) )
                    end
                    schema = string.lower(string.sub(packet:sub(2),openAfter+1,closeBefore-1))
                    if is_debug then
                        print("read_query:schema: " .. schema )
                    end
	                local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
                    if mapped then
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
                            proxy.queries:append(9, string.char(proxy.COM_QUERY) .. string.sub(packet:sub(2),1,openAfter) .. schema .. string.sub(packet:sub(2),closeBefore), { resultset_is_needed = true } )
                            print("read_query:substituted: schema `" .. schema .. "` in a routineSchema statement" )
                            if is_debug then
                                print("read_query:put a hook in for routine schema." )
                            end
                            return proxy.PROXY_SEND_QUERY
                        end
                    end
                end
    
-- 6) TRIGGER SCHEMA
            elseif triggerSchema then
                -- ends with WHERE trigger_schema = 'model_schema'
                print("read_query:found a trigger schema." )
                packetAfter = string.sub(packet:sub(2),triggerSchema,#packet:sub(2))
                if is_debug then
                    print("read_query:packetAfter = " .. packetAfter )
                end
                openAfter = string.find ( packetAfter, "'" )
                if openAfter then
                    if is_debug then
                        print("read_query:The openAfter is at " .. openAfter )
                    end
                    openAfter = openAfter + triggerSchema - 1
                    closeBefore = string.find ( string.sub(packet:sub(2),openAfter +1), "'" ) + openAfter
                    if is_debug then
                        print("read_query:The closeBefore is at " .. closeBefore )
                        print("read_query:The length is " .. (closeBefore - openAfter -1) )
                    end
                    schema = string.lower(string.sub(packet:sub(2),openAfter+1,closeBefore-1))
                    if is_debug then
                        print("read_query:schema: " .. schema )
                    end
	                local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
                    if mapped then
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
                            proxy.queries:append(6, string.char(proxy.COM_QUERY) .. string.sub(packet:sub(2),1,openAfter) .. schema .. string.sub(packet:sub(2),closeBefore), { resultset_is_needed = true } )
                            if is_debug then
                                print("read_query:substituted: schema `" .. schema .. "` in a triggerSchema statement" )
                                print("read_query:put a hook in for select trigger." )
                            end
                            return proxy.PROXY_SEND_QUERY
                        end
                    end
                end
            end -- end schema elseif
            -- end select if

-- 10) DROP SCHEMA IF EXISTS `server_schema`
        elseif string.lower(command) == "drop" then
            print("read_query:DROP packet: " .. packet:sub(2) )
            if option and string.lower(option) == "schema" then
                print("read_query:ignore DROP SCHEMA")
                -- Don't send to to the server just reply with a happy result to the client
                proxy.response = { type = proxy.MYSQLD_PACKET_OK, }
                return proxy.PROXY_SEND_RESULT
            end
            -- I'm not sure that I want to let it drop tables for that matter.
            -- Or at least not if that contain wp
            if option and string.lower(option) == "table" then
                isWordPress = string.find (packet:sub(2), "wp_")
                if isWordPress then
                    print("read_query:ignore DROP TABLE")
                    -- Don't send to to the server just reply with a happy result to the client
                    proxy.response = { type = proxy.MYSQLD_PACKET_OK, }
                    return proxy.PROXY_SEND_RESULT
                end
            end
    
-- 11) ALTER TABLE `model_schema`.`Entity` ..... *[ REFERENCES `model_schema`.`Entity`..... ]*
        elseif string.lower(command) == "alter" then
            print("read_query:ALTER TABLE/VIEW packet: " .. packet:sub(2) )
	        local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
            if mapped and option and ( string.lower(option) == "table" or string.lower(option) == "view" ) then
                if is_debug then
                    print("read_query:found an alter table/view." )
                end
                completedPacket = string.char(proxy.COM_QUERY)
                unprocessedPacket = packet:sub(2)
                beginProcessing = 1
                repeat
                    if is_debug then
                        print("read_query:Loop begin:Modified ALTER TABLE/VIEW packet: " .. completedPacket )
                        print("read_query:Loop begin:Unprocessed ALTER TABLE/VIEW packet: " .. unprocessedPacket )
                    end
                    openAfter = string.find ( unprocessedPacket, "`", beginProcessing, true )
                    if openAfter then
                        if is_debug then
                            print("Found an opening quote")
                            print("read_query:The openAfter is at " .. openAfter )
                        end
                        closeBefore = string.find ( string.sub(unprocessedPacket, openAfter +1), "`" ) + openAfter
                        if is_debug then
                            print("read_query:The closeBefore is at " .. closeBefore )
                            print("read_query:The length is " .. (closeBefore - openAfter -1) )
                        end
                        schema = string.lower(string.sub(unprocessedPacket,openAfter+1,closeBefore-1))
                        if is_debug then
                            print("read_query:schema: " .. schema )
                        end
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
                            completedPacket = completedPacket .. string.sub(unprocessedPacket,1,openAfter) .. schema .. string.sub(unprocessedPacket,closeBefore,closeBefore)
                        else
                            completedPacket = completedPacket .. string.sub(unprocessedPacket,1,closeBefore)
                        end
                        if ( closeBefore < #unprocessedPacket ) then
                            unprocessedPacket = string.sub(unprocessedPacket,closeBefore+1)  -- behaviour of sub where offset>length is undefined so avoid it
                        else
                            unprocessedPacket = ''
                        end
                    else
                        completedPacket = completedPacket .. unprocessedPacket
                        unprocessedPacket = ''
                    end
                    beginProcessing = string.find (string.lower(unprocessedPacket), "references")
                until not beginProcessing
                completedPacket = completedPacket .. unprocessedPacket
                print("read_query:Final modified ALTER TABLE/VIEW packet: " .. completedPacket )
                proxy.queries:append(11, completedPacket, { resultset_is_needed = true } )
                return proxy.PROXY_SEND_QUERY
            end

-- 12) CREATE TABLE IF NOT EXISTS `model_schema`.....
-- 13) CREATE OR REPLACE VIEW `model_schema`....
        elseif string.lower(command) == "create" or string.lower(command) == "replace" then
            print("read_query:CREATE/REPLACE packet: " .. packet:sub(2) )
            if option and ( string.lower(option) == "table" or string.lower(option) == "view" ) then
                if is_debug then
                    print("read_query:found a create/replace table/view." )
                end
                openAfter = string.find ( packet:sub(2), "`" )
                if openAfter then
                    if is_debug then
                        print("read_query:The openAfter is at " .. openAfter )
                    end
                    closeBefore = string.find ( string.sub(packet:sub(2),openAfter +1), "`" ) + openAfter
                    if is_debug then
                        print("read_query:The closeBefore is at " .. closeBefore )
                        print("read_query:The length is " .. (closeBefore - openAfter -1) )
                    end
                    schema = string.lower(string.sub(packet:sub(2),openAfter+1,closeBefore-1))
                    if is_debug then
                        print("read_query:schema: " .. schema )
                    end
                    local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
                    if mapped then
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
                            proxy.queries:append(12, string.char(proxy.COM_QUERY) .. string.sub(packet:sub(2),1,openAfter) .. schema .. string.sub(packet:sub(2),closeBefore), { resultset_is_needed = true } )
                            print("read_query:substituted: schema `" .. schema .. "` in a create/replace table/view statement" )
                            if is_debug then
                                print("read_query:put a hook in for create/replace table/view." )
                            end
                            return proxy.PROXY_SEND_QUERY
                        end
                    end
                end
            end
    
            -- This is the first use of the schema name held in the model.
            -- SHOW CREATE SCHEMA `server_schema`
        elseif string.lower(command) == "show" and option then
            if string.lower(option) == "create" then
                print("read_query:packet: " .. packet:sub(2) )
                -- SHOW CREATE SCHEMA `server_schema`
                openAfter = string.find (packet:sub(2), "`")
                if openAfter then
                    closeBefore = string.find ( string.sub(packet:sub(2),openAfter +1), "`" ) + openAfter
                    schema = string.lower(string.sub(packet:sub(2),openAfter+1,closeBefore-1))
                    if is_debug then
                        print("read_query:schema: " .. schema )
                    end
                    local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
                    if mapped then
                        if not mapped.client_schema and schema ~= 'information_schema' then
                            print("read_query:Setting the >>>client/model schema to be: " .. schema .. "<<<" )
                            mapped['client_schema'] = schema -- The schema name used by the model -- Mapped is a reference to the global
                        end
                        if schema == mapped.client_schema then
                            schema = mapped.server_schema
	                        proxy.queries:append(5, string.char(proxy.COM_QUERY) .. "SHOW CREATE SCHEMA `" .. schema .. "`")
                            print("read_query:substituted: SHOW CREATE SCHMEMA `" .. schema .. "`" )
                            return proxy.PROXY_SEND_QUERY
                        end
                    end
                end
            end

        end -- end command if/elseif cascade
    end -- end if COM_QUERY
end

function read_query_result(result)

    local is_debug = proxy.global.config.map_schema_is_debug
    local resultset = result.resultset
    local resultId = result.id

    if result.resultset.query_status == proxy.MYSQLD_PACKET_ERR or resultset.query_status < 0 then
        -- Raw only exists if result resultset_is_needed ~= true  i.e. not equal
        local err_code     = result.resultset.raw:byte(2) + (result.resultset.raw:byte(3) * 256)
        local err_sqlstate = result.resultset.raw:sub(5, 9)
        local err_msg      = result.resultset.raw:sub(10)

        print("read_query_result:Sending error result for " .. result.id .. " with error code: " .. err_code .. ".")
        if err_code == 1064 then   -- Syntax
            print(("read_query_result:Received a syntax ERROR (%d, %s)."):format(
                err_code,
                err_msg))
        end

        proxy.queries:reset() -- Empty queue
        return
    end

    if is_debug then
        print("read_query_result:A valid response was received for " .. resultId)
    end
    print("read_query_result:query-time: " .. (result.query_time / 1000) .. "ms")
    print("read_query_result:response-time: " .. (result.response_time / 1000) .. "ms")

    if resultId == 3 then
        print("read_query_result:result 3 found")
        local schemaIndex = nil
        local nameIndex = nil
        for n = 1, #resultset.fields do
            if is_debug then
                print("read_query_result:field:" .. resultset.fields[n].name .. ".");
            end
            if string.lower( resultset.fields[n].name ) == 'schema' then
                schemaIndex = n
            elseif string.lower( resultset.fields[n].name ) == 'name' then
                nameIndex = n
            end
        end
        if is_debug then
            print("read_query_result:searched for fields")
        end
        if schemaIndex and nameIndex then
            if is_debug then
                print("read_query_result:schemaIndex:" .. schemaIndex .. " nameIndex:" .. nameIndex )
            end

	        local mapped = proxy.global.config.map_schema[proxy.connection.client.username]
            if is_debug then
                print("read_query:username: " .. proxy.connection.client.username .. " as " .. tostring(mapped) )
            end
            local rowsResult = { }
            for row in resultset.rows do
                local schema
                schema = row[schemaIndex]
	            if mapped and schema == mapped.server_schema then
                    if mapped.client_schema then
                        schema = mapped.client_schema -- Opposite of the schema swap in read_query
                        print("read_query_result: Modifying schema from: " .. row[schemaIndex] .. " to " .. schema)
                    else 
                        schema = proxy.global.config.map_schema_default
                        print("read_query_result: Defaulting the model schema to : " .. schema)
                    end
                end
                row[schemaIndex] = schema

                schema = row[nameIndex]
	            if mapped and schema == mapped.server_schema then
                    if mapped.client_schema then
                        schema = mapped.client_schema -- Opposite of the schema swap in read_query
                        print("read_query_result: Modifying schema from: " .. row[nameIndex] .. " to " .. schema)
                    else 
                        schema = proxy.global.config.map_schema_default
                        print("read_query_result: Defaulting the model schema to : " .. schema)
                    end
                end
                row[nameIndex] = schema

                rowsResult[#rowsResult+1] = row
            end
            proxy.response.type = proxy.MYSQLD_PACKET_OK
            proxy.response.resultset = {
                fields = {
                    { type = proxy.MYSQL_TYPE_STRING, name = "OBJECT_TYPE", },
                    { type = proxy.MYSQL_TYPE_STRING, name = "CATALOG", },
                    { type = proxy.MYSQL_TYPE_STRING, name = "SCHEMA", },
                    { type = proxy.MYSQL_TYPE_STRING, name = "NAME", },
                },
                rows = rowsResult
            }
            print("read_query_result:returning with new resultset ")
            return proxy.PROXY_SEND_RESULT
        end
        return -- Will also send the result
    elseif resultId == 11 then
        print("read_query_result:returning from alter statement")
        return
    end -- End the resultID elseif
    return -- Will also send the result
end


