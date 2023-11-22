import json
# import zlib
import gzip

import os
import subprocess
import os.path

basedir = 'dist/dolphin-2.2.1-mistral-7b-q4f16_1/'

cache_file_path = os.path.join(basedir, "ndarray-cache.json")

# Load the ndarray-cache.json file
with open(cache_file_path, "r") as file:
    ndarray_cache = json.load(file)


for rec in ndarray_cache["records"]:
    if rec['format'] == 'raw-shard':

        

        original_file_path = os.path.join(basedir, rec['dataPath'])
        new_file_path = original_file_path + '.lz4'

        subprocess.run(['lz4', '--best', '--favor-decSpeed', '-f',  '-z', original_file_path, new_file_path], check=True)

        original_file_size = os.path.getsize(original_file_path)
        compressed_file_size = os.path.getsize(new_file_path)
        compression_ratio = compressed_file_size / original_file_size

        if compression_ratio < 0.95:
            print('Compressing', new_file_path)
            rec['dataPath'] = rec['dataPath'] + '.lz4'
            rec['format'] = 'lz4-shard'
        else:
            print('Removed', new_file_path)
            os.remove(new_file_path)
        

        # Read the original data, compress it and write out to new file
        # with gzip.open(new_file_path, 'wb') as compressed_file:
        #     with open(original_file_path, 'rb') as original_file:
        #         original_data = original_file.read()
        #         compressed_file.write(original_data)
        #         # compressed_data = zlib.compress(original_data, level=9)

        

        # with open(new_file_path, 'wb') as compressed_file:
        #     compressed_file.write(compressed_data)


# Save the modified ndarray-cache.json file with indentation
with open(cache_file_path, "w") as file:
    json.dump(ndarray_cache, file, indent=4)


for rec in ndarray_cache["records"]:
    if rec['format'] == 'lz4-shard':
        original_file_path = os.path.join(basedir, rec['dataPath'].replace('.lz4', ''))
        if os.path.exists(original_file_path):
            os.remove(original_file_path)