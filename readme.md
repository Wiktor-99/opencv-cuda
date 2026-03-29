docker build -t opencv-cuda .
docker run --rm -v $(pwd)/output:/output opencv-cuda