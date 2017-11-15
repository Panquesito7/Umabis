-- TODO: privileges management
local commands_descriptors = {}
commands_descriptors.help = {
	description = "print help about a subcommand or list all subcommands",
	usage = "[<subcommand>]",
	params = 0,
	func = function(name, token, cmd)
		local function get_string_or_func(str_or_func)
			if type(str_or_func) == "string" then
				return str_or_func
			else
				return str_or_func(name)
			end
		end

		if not cmd then
			local str = "Available subcommands:\n"
			for cmd, dsc in pairs(commands_descriptors) do
				str = str .. "  " .. cmd .. " - " .. dsc.description .. "\n"
			end
			str = str .. "Type /umabis help <subcommand> to get help about a subcommand."
			return true, str
		end

		local descriptor = commands_descriptors[cmd]
		if not descriptor then
			return false, "Subcommand " .. cmd .. " does not exist. Type /umabis help for a list of available subcommands."
		end

		if descriptor.privs then
			for _, priv in ipairs(descriptor.privs) do
				if not minetest.check_player_privs(name, priv) then
					return false, "You don't have permission to run this command. Missing privilege: "..priv
				end
			end
		end

		if descriptor.additional_info then
			return true, "/umabis " .. cmd .. " " .. descriptor.usage .. "\n" ..
			             descriptor.description .. "\n" ..
				     get_string_or_func(descriptor.additional_info)
		else
			return true, "/umabis " .. cmd .. " " .. descriptor.usage .. "\n" ..
			             descriptor.description
		end
	end
}
commands_descriptors.reload = {
	description = "reload Umabis",
	usage = "",
	additional_info = "using this command will apply any change made in a file of the mod, except in init.lua",
	privs = {"ban"},
	params = 0,
	func = function(name, token)
		if umabis.reload() then
			return true, "Successfully reloaded Umabis."
		else
			return false, minetest.colorize("#FF0000", "Error occured while reloading. See debug.txt for more details. Umabis is currently is a very inconsistent state, please reload again as soon as possible.")
		end
	end
}
commands_descriptors.blacklist = {
	description = "globally blacklist a user",
	usage = "<nick> <reason> <category> [<time>]",
	-- TODO: add available categories in additional_info.
	additional_info = function()
		local str = "Format of <time>:\n"..
	                    "* 1s or 1 - one second\n"..
		            "* 1m - one minute\n"..
		            "* 1h - one hour\n"..
		            "* 1D - one day\n"..
		            "* 1W - one week\n"..
		            "* 1M - one month (30 days)\n"..
		            "* 1Y - one year (360 days)\n"..
		            "Values can be combined. For example \"1D3h3m7s\" will blacklist for 1 day, 3 hours, 3 minutes, and 7 seconds.\n\n"..
			    "Available categories are:\n"
		for category, description in pairs(umabis.serverapi.params.available_blacklist_categories) do
			str = str .. "* " .. category .. " - " .. description .. "\n"
		end
		return str
	end,
	params = 3,
	func = function(name, token, blacklisted_name, reason, category, time)
		-- Thanks xban2!
		local function parse_time(t) --> secs
			local unit_to_secs = {
				s = 1, m = 60, h = 3600,
				D = 86400, W = 604800, M = 2592000, Y = 31104000,
				[""] = 1,
			}

			local secs = 0
			for num, unit in t:gmatch("(%d+)([smhDWMY]?)") do
				secs = secs + (tonumber(num) * (unit_to_secs[unit] or 1))
			end
			return secs
		end

		print("Running the blacklist_user command")
		local ok, err = umabis.serverapi.blacklist_user(name, token, blacklisted_name, reason, category, time and parse_time(time))
		if not ok then
			return false, err
		end
		return true, "Blacklisted "..blacklisted_name
	end
}

minetest.register_chatcommand("umabis", {
	params = "<subcommand> [<subcommand parameters...>]",
	description = "Umabis chatcommand interface",
	privs = {},
	func = function(name, paramstr)
		local params = paramstr:split(" ")
		local subcmd = params[1]
		if not subcmd then
			return false, "Please specify a subcommand. Refer to /help umabis and /umabis help for help"
		end

		local scmd_dscptr = commands_descriptors[subcmd]
		if not scmd_dscptr then
			return false, "Invalid subcommand: "..subcmd..". See /umabis help for a list of available subcommands"
		end

		local scmd_params = {}
		local i = 2
		while i <= #params do
			-- Quotes-enclosed strings are treated as a single parameter
			if string.sub(params[i], 1, 1) == "\"" then
				local p = params[i]

				local j = i
				repeat
					j = j + 1
					if not params[j] then
						return false, "Unclosed quote"
					end
					p = p.." "..params[j]
				until string.sub(params[j], string.len(params[j])) == "\""

				table.insert(scmd_params, string.sub(p, 2, string.len(p)-1))
				i = j + 1
			else
				table.insert(scmd_params, params[i])
				i = i + 1
			end
		end

		if #scmd_params < scmd_dscptr.params then
			return false, "Subcommand "..subcmd.." requires at least "..scmd_dscptr.params.." parameters, given "..#scmd_params..". See /umabis help "..subcmd.." for help."
		end

		return scmd_dscptr.func(name, umabis.session.sessions[name].token, unpack(scmd_params))
	end
})

if umabis.register_on_reload then -- If first loading
	umabis.register_on_reload(function()
		minetest.unregister_chatcommand("umabis")
	end)
end
