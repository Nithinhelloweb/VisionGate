import json
import re

def parse_thirukkural():
    input_file = "thirukkural.md"
    output_file = "assets/thirukkural.json"
    
    kurals = []
    current_adhigaram = ""
    
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        if line.startswith("### "):
            current_adhigaram = line.replace("### ", "").strip()
            i += 1
            continue
            
        # Match "1. " or "1330. "
        match = re.match(r"^(\d+)\.\s+(.*)", line)
        if match:
            kural_no = int(match.group(1))
            line1_raw = match.group(2).strip()
            
            # The next line should be the second line of the kural
            if i + 1 < len(lines):
                line2_raw = lines[i+1].strip()
                
                # Clean up any trailing dots or extra spaces
                # Reconstruct strictly as 4 words and 3 words if possible, but
                # usually the source text is already split correctly.
                # However, to guarantee 4 and 3:
                full_text = f"{line1_raw} {line2_raw}".replace("  ", " ").strip()
                words = [w for w in full_text.split(" ") if w]
                
                if len(words) >= 7:
                    l1 = " ".join(words[:4])
                    l2 = " ".join(words[4:])
                else:
                    l1 = line1_raw
                    l2 = line2_raw
                    
                kurals.append({
                    "no": kural_no,
                    "adhigaram": current_adhigaram,
                    "line1": l1,
                    "line2": l2
                })
                i += 1 # skip line 2
        i += 1
        
    print(f"Parsed {len(kurals)} kurals.")
    
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(kurals, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    parse_thirukkural()
