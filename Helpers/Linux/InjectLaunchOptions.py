import sys
import os
import re

def inject_launch_options(vdf_path, app_id):
    if not os.path.exists(vdf_path):
        return False

    with open(vdf_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    app_pattern = re.compile(rf'^\s*"{app_id}"\s*$')
    
    app_line_idx = -1
    for idx, line in enumerate(lines):
        if app_pattern.match(line):
            app_line_idx = idx
            break
            
    required_val = 'WINEDLLOVERRIDES=\\"dwmapi=n,b\\" %command%'
            
    if app_line_idx == -1:
        # App ID block doesn't exist yet! Let's find the "Apps" block and insert it.
        apps_pattern = re.compile(r'^\s*"Apps"\s*$')
        apps_line_idx = -1
        for idx, line in enumerate(lines):
            if apps_pattern.match(line):
                apps_line_idx = idx
                break
        if apps_line_idx == -1:
            return False
            
        open_brace_idx = -1
        for idx in range(apps_line_idx + 1, len(lines)):
            if '{' in lines[idx]:
                open_brace_idx = idx
                break
        if open_brace_idx == -1:
            return False
            
        # Get indentation of the "Apps" block opening brace or line before
        indent_match = re.match(r'^([ \t]*)', lines[apps_line_idx])
        apps_indent = indent_match.group(1) if indent_match else "\t\t\t\t"
        child_indent = apps_indent + "\t"
        
        new_block = [
            f'{child_indent}"{app_id}"\n',
            f'{child_indent}{{\n',
            f'{child_indent}\t"LaunchOptions"\t\t"{required_val}"\n',
            f'{child_indent}}}\n'
        ]
        lines = lines[:open_brace_idx+1] + new_block + lines[open_brace_idx+1:]
    else:
        open_brace_idx = -1
        for idx in range(app_line_idx + 1, len(lines)):
            if '{' in lines[idx]:
                open_brace_idx = idx
                break
        if open_brace_idx == -1:
            return False
            
        close_brace_idx = -1
        brace_count = 1
        for idx in range(open_brace_idx + 1, len(lines)):
            if '{' in lines[idx]:
                brace_count += 1
            if '}' in lines[idx]:
                brace_count -= 1
                if brace_count == 0:
                    close_brace_idx = idx
                    break
        if close_brace_idx == -1:
            return False
            
        # Search for "LaunchOptions" inside the App ID block
        launch_opt_pattern = re.compile(r'^\s*"LaunchOptions"\s+.*$')
        launch_opt_idx = -1
        for idx in range(open_brace_idx + 1, close_brace_idx):
            if launch_opt_pattern.match(lines[idx]):
                launch_opt_idx = idx
                break
                
        if launch_opt_idx != -1:
            current_line = lines[launch_opt_idx]
            # Match current value supporting escaped quotes
            val_match = re.search(r'"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"', current_line)
            if val_match:
                current_val = val_match.group(1)
                if 'dwmapi=n,b' not in current_val:
                    if '%command%' in current_val:
                        # Replace %command% with WINEDLLOVERRIDES="dwmapi=n,b" %command%
                        new_val = current_val.replace('%command%', required_val)
                    else:
                        new_val = f'{required_val} {current_val}'
                    indent_match = re.match(r'^([ \t]*)', current_line)
                    indent = indent_match.group(1) if indent_match else "\t\t\t\t\t\t"
                    lines[launch_opt_idx] = f'{indent}"LaunchOptions"\t\t"{new_val}"\n'
            else:
                # If extraction failed, replace it
                indent_match = re.match(r'^([ \t]*)', current_line)
                indent = indent_match.group(1) if indent_match else "\t\t\t\t\t\t"
                lines[launch_opt_idx] = f'{indent}"LaunchOptions"\t\t"{required_val}"\n'
        else:
            # "LaunchOptions" key does not exist. Add it.
            indent_match = re.match(r'^([ \t]*)', lines[open_brace_idx])
            parent_indent = indent_match.group(1) if indent_match else "\t\t\t\t\t"
            child_indent = parent_indent + "\t"
            lines.insert(open_brace_idx + 1, f'{child_indent}"LaunchOptions"\t\t"{required_val}"\n')
            
    with open(vdf_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    return True

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 InjectLaunchOptions.py <steam_root> <app_id>")
        sys.exit(1)
        
    steam_root = sys.argv[1]
    app_id = sys.argv[2]
    
    userdata_dir = os.path.join(steam_root, 'userdata')
    if not os.path.isdir(userdata_dir):
        print(f"Userdata directory not found: {userdata_dir}")
        sys.exit(1)
        
    success = False
    for user_id in os.listdir(userdata_dir):
        vdf_path = os.path.join(userdata_dir, user_id, 'config', 'localconfig.vdf')
        if os.path.isfile(vdf_path):
            print(f"Injecting launch options into {vdf_path}")
            if inject_launch_options(vdf_path, app_id):
                success = True
                
    if success:
        print("Successfully injected Steam launch options.")
    else:
        print("No localconfig.vdf files modified.")
