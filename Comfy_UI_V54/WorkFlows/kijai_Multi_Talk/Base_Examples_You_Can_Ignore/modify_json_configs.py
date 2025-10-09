#!/usr/bin/env python3
"""
Script to modify JSON workflow configurations based on base file differences.

This script modifies 3 key parameters in JSON files:
1. WanVideoLoraSelect bypass status (mode: 0=enabled, 4=bypassed)
2. WanVideoLoraSelect lora weight (widgets_values[1])
3. WanVideoModelLoader base model (widgets_values[0])
"""

import json
import os
import glob
from pathlib import Path

# Configuration templates based on base file analysis
CONFIGURATIONS = {
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

def modify_json_file(file_path, config):
    """Modify a single JSON file with the given configuration."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Flag to track if any changes were made
        changes_made = False
        
        # Find and modify WanVideoLoraSelect node
        lora_node = find_node_by_type(data["nodes"], "WanVideoLoraSelect")
        if lora_node:
            # Update mode (bypass status)
            if lora_node.get("mode") != config["lora_bypass_mode"]:
                lora_node["mode"] = config["lora_bypass_mode"]
                changes_made = True
                print(f"  Updated WanVideoLoraSelect mode to {config['lora_bypass_mode']}")
            
            # Update lora weight (widgets_values[1])
            if len(lora_node.get("widgets_values", [])) > 1:
                current_weight = lora_node["widgets_values"][1]
                if abs(current_weight - config["lora_weight"]) > 0.001:  # account for floating point precision
                    lora_node["widgets_values"][1] = config["lora_weight"]
                    changes_made = True
                    print(f"  Updated WanVideoLoraSelect weight from {current_weight} to {config['lora_weight']}")
        
        # Find and modify WanVideoModelLoader node
        model_node = find_node_by_type(data["nodes"], "WanVideoModelLoader")
        if model_node:
            # Update base model (widgets_values[0])
            if len(model_node.get("widgets_values", [])) > 0:
                current_model = model_node["widgets_values"][0]
                if current_model != config["base_model"]:
                    model_node["widgets_values"][0] = config["base_model"]
                    changes_made = True
                    print(f"  Updated base model from '{current_model}' to '{config['base_model']}'")
        
        # Write back to file if changes were made
        if changes_made:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print(f"  ✓ Successfully updated {file_path}")
        else:
            print(f"  - No changes needed for {file_path}")
            
    except Exception as e:
        print(f"  ✗ Error processing {file_path}: {str(e)}")

def main():
    """Main function to process all target folders."""
    print("=== JSON Configuration Modifier ===")
    print("Modifying JSON files in target folders...\n")
    
    # Process each target folder
    for folder_name, config in CONFIGURATIONS.items():
        folder_path = Path(folder_name)
        
        if not folder_path.exists():
            print(f"⚠️  Folder '{folder_name}' does not exist. Skipping...")
            continue
        
        print(f"📁 Processing folder: {folder_name}")
        print(f"   Config: Lora mode={config['lora_bypass_mode']}, weight={config['lora_weight']}")
        print(f"   Base model: {config['base_model']}")
        
        # Find all JSON files in the folder
        json_files = list(folder_path.glob("*.json"))
        
        if not json_files:
            print(f"   No JSON files found in {folder_name}")
            continue
        
        # Process each JSON file
        for json_file in json_files:
            print(f"   Processing: {json_file.name}")
            modify_json_file(json_file, config)
        
        print(f"   Completed folder: {folder_name}\n")
    
    print("=== Processing Complete ===")

if __name__ == "__main__":
    main() 