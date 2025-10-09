#!/usr/bin/env python3
"""
Verification script to check if all JSON configurations were applied correctly.

This script verifies the 3 key parameters in all JSON files:
1. WanVideoLoraSelect bypass status (mode: 0=enabled, 4=bypassed)
2. WanVideoLoraSelect lora weight (widgets_values[1])
3. WanVideoModelLoader base model (widgets_values[0])
"""

import json
import os
from pathlib import Path
from collections import defaultdict

# Expected configurations
EXPECTED_CONFIGS = {
    "Loyal_Medium_Animated": {
        "lora_bypass_mode": 4,  # bypassed
        "lora_weight": 0.6,
        "base_model": "Wan2.1_14b_FusionX_Image_to_Video_GGUF_Q8.gguf"
    },
    "Less_Loyal_More_Animated": {
        "lora_bypass_mode": 0,  # enabled
        "lora_weight": 0.6,
        "base_model": "Wan2.1_14b_FusionX_Image_to_Video_GGUF_Q8.gguf"
    },
    "Lesser_Loyal_Super_Animated": {
        "lora_bypass_mode": 0,  # enabled
        "lora_weight": 1.0,
        "base_model": "Wan2.1_14b_FusionX_Image_to_Video_GGUF_Q8.gguf"
    }
}

def find_node_by_type(nodes, node_type):
    """Find a node by its type in the nodes list."""
    for node in nodes:
        if node.get("type") == node_type:
            return node
    return None

def verify_json_file(file_path, expected_config):
    """Verify a single JSON file against expected configuration."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        issues = []
        
        # Check WanVideoLoraSelect node
        lora_node = find_node_by_type(data["nodes"], "WanVideoLoraSelect")
        if lora_node:
            # Check mode (bypass status)
            actual_mode = lora_node.get("mode")
            expected_mode = expected_config["lora_bypass_mode"]
            if actual_mode != expected_mode:
                issues.append(f"WanVideoLoraSelect mode: expected {expected_mode}, got {actual_mode}")
            
            # Check lora weight
            if len(lora_node.get("widgets_values", [])) > 1:
                actual_weight = lora_node["widgets_values"][1]
                expected_weight = expected_config["lora_weight"]
                if abs(actual_weight - expected_weight) > 0.001:
                    issues.append(f"WanVideoLoraSelect weight: expected {expected_weight}, got {actual_weight}")
            else:
                issues.append("WanVideoLoraSelect widgets_values missing or insufficient")
        else:
            issues.append("WanVideoLoraSelect node not found")
        
        # Check WanVideoModelLoader node
        model_node = find_node_by_type(data["nodes"], "WanVideoModelLoader")
        if model_node:
            # Check base model
            if len(model_node.get("widgets_values", [])) > 0:
                actual_model = model_node["widgets_values"][0]
                expected_model = expected_config["base_model"]
                if actual_model != expected_model:
                    issues.append(f"WanVideoModelLoader model: expected '{expected_model}', got '{actual_model}'")
            else:
                issues.append("WanVideoModelLoader widgets_values missing")
        else:
            issues.append("WanVideoModelLoader node not found")
        
        return issues
        
    except Exception as e:
        return [f"Error reading file: {str(e)}"]

def main():
    """Main verification function."""
    print("=== JSON Configuration Verification ===")
    print("Verifying all JSON files in target folders...\n")
    
    total_files = 0
    files_with_issues = 0
    all_issues = defaultdict(list)
    
    # Process each target folder
    for folder_name, expected_config in EXPECTED_CONFIGS.items():
        folder_path = Path(folder_name)
        
        if not folder_path.exists():
            print(f"⚠️  Folder '{folder_name}' does not exist. Skipping...")
            continue
        
        print(f"📁 Verifying folder: {folder_name}")
        print(f"   Expected: Lora mode={expected_config['lora_bypass_mode']}, weight={expected_config['lora_weight']}")
        print(f"   Expected model: {expected_config['base_model']}")
        
        # Find all JSON files in the folder
        json_files = list(folder_path.glob("*.json"))
        
        if not json_files:
            print(f"   No JSON files found in {folder_name}")
            continue
        
        folder_issues = 0
        
        # Verify each JSON file
        for json_file in json_files:
            total_files += 1
            issues = verify_json_file(json_file, expected_config)
            
            if issues:
                files_with_issues += 1
                folder_issues += 1
                all_issues[folder_name].extend([(json_file.name, issues)])
                print(f"   ❌ {json_file.name}: {len(issues)} issue(s)")
                for issue in issues:
                    print(f"      - {issue}")
            else:
                print(f"   ✅ {json_file.name}: OK")
        
        if folder_issues == 0:
            print(f"   🎉 All files in {folder_name} are correctly configured!")
        else:
            print(f"   ⚠️  {folder_issues} file(s) with issues in {folder_name}")
        
        print()
    
    # Summary
    print("=== Verification Summary ===")
    print(f"Total files checked: {total_files}")
    print(f"Files with issues: {files_with_issues}")
    print(f"Files correctly configured: {total_files - files_with_issues}")
    
    if files_with_issues == 0:
        print("🎉 ALL CONFIGURATIONS ARE CORRECT! ✅")
    else:
        print(f"⚠️  {files_with_issues} file(s) need attention")
        
        print("\n=== Detailed Issues ===")
        for folder_name, folder_issues in all_issues.items():
            print(f"\n📁 {folder_name}:")
            for filename, issues in folder_issues:
                print(f"   📄 {filename}:")
                for issue in issues:
                    print(f"      - {issue}")
    
    print("\n=== Verification Complete ===")

if __name__ == "__main__":
    main() 