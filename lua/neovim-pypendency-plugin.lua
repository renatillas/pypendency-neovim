local M = {}

-- Function to get the relative path of the current file
local function get_relative_path()
	local full_path = vim.fn.expand("%:p")
	local cwd = vim.fn.getcwd()
	return full_path:sub(#cwd + 2) -- +2 to remove the leading slash
end

-- Function to create the YAML content
local function create_yaml_content(class_name, module_path)
	-- Remove 'src/' from the beginning of the module_path and extension
	local relative_module_path = module_path:gsub("^src/", ""):gsub("%.py$", "")
	local fqn = relative_module_path:gsub("/", ".") .. "." .. class_name
	return string.format(
		[[%s:
  fqn: %s
  args:
]],
		fqn,
		fqn
	)
end

-- Function to find the _dependency_injection folder
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
	-- Get the current buffer's information
	local buf = vim.api.nvim_get_current_buf()
	local filename = vim.fn.expand("%:t")
	local relative_path = get_relative_path()

	-- Extract class name (assuming it's the first class in the file)
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

	-- Find the _dependency_injection folder
	local di_folder, di_index = find_dependency_injection_folder(relative_path)
	if not di_folder then
		print("_dependency_injection folder not found in any parent directory.")
		return
	end

	-- Construct the YAML file path
	local path_parts = vim.split(relative_path, "/", { plain = true })
	local yaml_path = di_folder
	print(di_index + 1)
	print(#path_parts - 1)
	for i = di_index + 1, #path_parts - 1 do
		print(yaml_path)
		yaml_path = yaml_path .. "/" .. path_parts[i]
		print(yaml_path)
	end
	yaml_path = yaml_path .. "/" .. vim.fn.fnamemodify(filename, ":r") .. ".yaml"

	-- Create the directory if it doesn't exist
	vim.fn.mkdir(vim.fn.fnamemodify(yaml_path, ":h"), "p")

	-- Generate YAML content
	local yaml_content = create_yaml_content(class_name, relative_path)

	-- Write the YAML file
	local file = io.open(yaml_path, "w")
	if file then
		file:write(yaml_content)
		file:close()
		print("YAML file generated: " .. yaml_path)
	else
		print("Failed to create YAML file.")
	end
end

vim.api.nvim_create_user_command("GenerateYAML", function()
	require("neovim-pypendency-plugin").generate_yaml()
end, {})
return M
