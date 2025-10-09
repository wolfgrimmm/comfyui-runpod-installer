#!/usr/bin/env python3
"""
Simple script to replace model filename in all JSON config files.
Replaces: WanVideo_2_1_Multitalk_14B_fp8_e4m3fn.safetensors
With: WanVideo_2_1_Multitalk_14B_fp32.safetensors
"""

import os
import json
import glob
from pathlib import Path

def replace_in_json_files():
    """Replace the model filename in all JSON files in the workspace."""
    
    # Define the strings to replace
    old_string = "Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors"
    new_string = "Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64_fixed.safetensors"
    
    # Get current directory
    current_dir = Path(".")
    
    # Find all JSON files recursively
    json_files = list(current_dir.rglob("*.json"))
    
    print(f"Found {len(json_files)} JSON files to process...")
    
    files_modified = 0
    total_replacements = 0
    
    for json_file in json_files:
        try:
            # Read the file
            with open(json_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Check if the old string exists in the file
            if old_string in content:
                print(f"Processing: {json_file}")
                
                # Count occurrences before replacement
                count_before = content.count(old_string)
                
                # Replace the string
                new_content = content.replace(old_string, new_string)
                
                # Write back to file
                with open(json_file, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                
                files_modified += 1
                total_replacements += count_before
                print(f"  → Replaced {count_before} occurrence(s)")
            
        except Exception as e:
            print(f"Error processing {json_file}: {e}")
    
    print(f"\nSummary:")
    print(f"Files modified: {files_modified}")
    print(f"Total replacements made: {total_replacements}")
    print(f"Replaced '{old_string}' with '{new_string}'")

if __name__ == "__main__":
    print("Starting model filename replacement...")
    replace_in_json_files()
    print("Done!") 