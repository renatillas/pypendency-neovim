local M = {}

-- Cache to store YAML files
local yaml_cache = {}

-- Function to get the relative path of the current file
local function get_relative_path()
	local full_path = vim.fn.expand("%:p")
	local cwd = vim.fn.getcwd()
	return full_path:sub(#cwd + 2) -- +2 to remove the leading slash
end

-- Function to extract class arguments and their types
local function extract_class_args(lines, class_name)
	local args = {}
	local in_class = false
	local in_init = false
	local init_params = {}

	for _, line in ipairs(lines) do
		if not in_class and line:match("^class%s+" .. class_name) then
			in_class = true
		elseif in_class and (line:match("^%s*def%s+__init__") or line:match("^%s*__init__")) then
			in_init = true
		elseif in_init and line:match("^%s*%)%s*%-%>%s*None%s*:") then
			-- End of multi-line __init__ definition
			in_init = false
		elseif in_init then
			-- Extract parameters and their types from __init__ definition
			local param, param_type = line:match("%s*([%w_]+)%s*:%s*([%w_%.]+)")
			if param and param ~= "self" then
				table.insert(init_params, { name = param, type = param_type })
			end
		elseif not in_init and #init_params > 0 then
			-- Look for attribute assignments
			for _, param in ipairs(init_params) do
				local attr_match = line:match("^%s*self%.([%w_]+)%s*=%s*" .. param.name)
				local direct_match = line:match("^%s*self%.(" .. param.name .. ")%s*=%s*" .. param.name)
				if attr_match or direct_match then
					table.insert(args, param)
					break
				end
			end
		end
	end
	return args
end

-- Function to traverse the project and cache YAML files
local function cache_yaml_files()
	local root = vim.fn.getcwd()
	local yaml_files = vim.fn.glob(root .. "/**/_dependency_injection/**/*.yaml", false, true)

	for _, file in ipairs(yaml_files) do
		local content = vim.fn.readfile(file)
		local current_class = nil
		for _, line in ipairs(content) do
			local class_def = line:match("([^%.]+):$")
			if class_def then
				current_class = class_def
				yaml_cache[current_class] = line:sub(1, -2)
				break
			end
		end
	end
end

-- Function to find implementation for a type
local function find_implementation(type_name)
	for current_class, fqn in pairs(yaml_cache) do
		if string.find(current_class, type_name) then
			return fqn
		end
	end
	return nil
end

-- Function to create the YAML content
local function create_yaml_content(class_name, module_path, args)
	local relative_module_path = module_path:gsub("^src/", ""):gsub("%.py$", "")
	local fqn = relative_module_path:gsub("/", ".") .. "." .. class_name
	local content = string.format(
		[[%s:
  fqn: %s
  args:
]],
		fqn,
		fqn
	)

	for _, arg in ipairs(args) do
		local impl = find_implementation(arg.type)
		if impl then
			content = content .. string.format('    - "@%s"\n', impl)
		else
			content = content .. string.format('    - "@%s"\n', arg.name)
		end
	end

	return content
end

local function find_dependency_injection_folder(path)
	local parts = vim.split(path, "/", { plain = true })
	for i = #parts, 1, -1 do
		local test_path = table.concat(parts, "/", 1, i) .. "/_dependency_injection"
		if vim.fn.isdirectory(test_path) == 1 then
			return test_path, i
		end
	end
	return nil
end

-- Function to generate the YAML file
function M.generate_yaml()
	-- Cache YAML files if not already done
	if vim.tbl_isempty(yaml_cache) then
		cache_yaml_files()
	end

	-- Get the current buffer's information
	local buf = vim.api.nvim_get_current_buf()
	local filename = vim.fn.expand("%:t")
	local relative_path = get_relative_path()

	-- Extract class name and arguments
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local class_name
	for _, line in ipairs(lines) do
		class_name = line:match("^class%s+(%w+)")
		if class_name then
			break
		end
	end

	if not class_name then
		print("No class found in the current file.")
		return
	end

	local args = extract_class_args(lines, class_name)

	-- Find the _dependency_injection folder
	local di_folder, di_index = find_dependency_injection_folder(relative_path)
	if not di_folder then
		print("_dependency_injection folder not found in any parent directory.")
		return
	end

	-- Construct the YAML file path
	local path_parts = vim.split(relative_path, "/", { plain = true })
	local yaml_path = di_folder
	for i = di_index + 1, #path_parts - 1 do
		yaml_path = yaml_path .. "/" .. path_parts[i]
	end
	yaml_path = yaml_path .. "/" .. vim.fn.fnamemodify(filename, ":r") .. ".yaml"

	-- Check if the YAML file already exists
	if vim.fn.filereadable(yaml_path) == 1 then
		-- Open the existing YAML file and switch to it
		vim.cmd("edit " .. vim.fn.fnameescape(yaml_path))
		print("Opened existing YAML file: " .. yaml_path)
	else
		-- Create the directory if it doesn't exist
		vim.fn.mkdir(vim.fn.fnamemodify(yaml_path, ":h"), "p")

		-- Generate YAML content
		local yaml_content = create_yaml_content(class_name, relative_path, args)

		-- Write the YAML file
		local file = io.open(yaml_path, "w")
		if file then
			file:write(yaml_content)
			file:close()
			-- Open the newly created YAML file and switch to it
			vim.cmd("edit " .. vim.fn.fnameescape(yaml_path))
			print("YAML file generated and opened: " .. yaml_path)
		else
			print("Failed to create YAML file.")
		end
	end
end

vim.api.nvim_create_user_command("GenerateYAML", function()
	require("neovim-pypendency-plugin").generate_yaml()
end, {})

return M
