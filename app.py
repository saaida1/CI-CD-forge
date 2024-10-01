import os
import subprocess
import shutil
from flask import Flask, request, jsonify, render_template
import re

app = Flask(__name__)

WORKSPACE_BASE_PATH = './terraform_workspaces/'

def validate_github_url(url):
    github_pattern = r'^https?://github\.com/[\w-]+/[\w.-]+$'
    return bool(re.match(github_pattern, url))

@app.route('/')
def index():
    return render_template('form.html')

@app.route('/submit_tokens', methods=['POST'])
def create_infrastructure():
    # Get user-specific data from the request
    data = request.form
    user_id = data.get('user_id')
    git_username = data.get('git_username')
    git_token = data.get('git_token')
    git_repo = data.get('git_repo')
    git_branch = data.get('git_branch', 'main')  # Default to 'main' if not provided
    docker_username = data.get('docker_username')
    docker_token = data.get('docker_token')

    # Validate required fields
    if not all([user_id, git_username, git_token, git_repo, docker_username, docker_token]):
        return jsonify({"error": "Missing required fields"}), 400

    # Validate GitHub URL format
    if not validate_github_url(git_repo):
        return jsonify({"error": "Invalid GitHub repository URL"}), 400

    # Create a unique directory for the user (workspace)
    user_workspace = os.path.join(WORKSPACE_BASE_PATH, user_id)

    try:
        # Check if the workspace already exists
        if not os.path.exists(user_workspace):
            os.makedirs(user_workspace)

        # Copy the base Terraform configuration files to the user's workspace
        shutil.copyfile('main.tf', os.path.join(user_workspace, 'main.tf'))
        shutil.copyfile('variables.tf', os.path.join(user_workspace, 'variables.tf'))

        # Set user-specific environment variables
        env = os.environ.copy()
        env.update({
            'TF_VAR_git_username': git_username,
            'TF_VAR_git_token': git_token,
            'TF_VAR_git_repo': git_repo,
            'TF_VAR_git_branch': git_branch,
            'TF_VAR_docker_username': docker_username,
            'TF_VAR_docker_token': docker_token
        })

        # Update the user_data.sh script with the repository information
        user_data_template = os.path.join(user_workspace, 'user_data.sh')
        with open('user_data.sh', 'r') as f:
            script_content = f.read()
        
        # Replace placeholders in the script
        updated_script = script_content.replace('${git_repo}', git_repo)
        updated_script = updated_script.replace('${git_branch}', git_branch)
        
        with open(user_data_template, 'w') as f:
            f.write(updated_script)

        # Initialize and apply Terraform within the user's workspace
        subprocess.run(['terraform', 'init'], check=True, cwd=user_workspace, env=env)
        subprocess.run(['terraform', 'plan', '-out=tfplan'], check=True, cwd=user_workspace, env=env)
        subprocess.run(['terraform', 'apply', '-auto-approve', 'tfplan'], check=True, cwd=user_workspace, env=env)

        return jsonify({
            "message": f"Infrastructure setup completed for user {user_id}",
            "repository": git_repo,
            "branch": git_branch
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)