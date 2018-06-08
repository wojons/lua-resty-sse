max_line_length = false
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false
stds.ngx = {
  globals = {"ngx","unpack"}
}
std = "+ngx"
files["test"] = {std = "+busted"}
