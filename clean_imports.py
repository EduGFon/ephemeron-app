import os

for root, dirs, files in os.walk("/home/edu/p/ephemeron/lib"):
    for file in files:
        if file.endswith(".dart"):
            path = os.path.join(root, file)
            with open(path, "r") as f:
                content = f.read()
            
            if "import 'package:flutter_animate/flutter_animate.dart';" in content:
                content = content.replace("import 'package:flutter_animate/flutter_animate.dart';\n", "")
                with open(path, "w") as f:
                    f.write(content)

