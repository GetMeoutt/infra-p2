#!/bin/bash
# Teardown script - removes all resources
echo "Removing all video-app resources..."
kubectl delete namespace video-app
echo "Done. All resources removed."
