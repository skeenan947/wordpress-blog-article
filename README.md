# Deploying stateful legacy applications on Google Cloud with Cloud Run & Filestore
## Summary
Stateful applications can be difficult to deploy to cloud-based infrastructures, especially when they are legacy applications, and it's important to understand the nuances of the process. In this blog post, we'll explore how to deploy stateful legacy applications on Google Cloud with Cloud Run and Filestore, using WordPress as an example, due to its' reliance on the filesystem for state

## Why Cloud Run & Filestore
Cloud Run is a serverless compute platform offered by the Google Cloud Platform. It is designed to run stateless containers.  Cloud Run supports web apps and microservices, and it can easily be used to deploy and autoscale applications.  In this post, we're going to deploy WordPress, a stateful application, as managing apps with Cloud Run is far simpler than deploying on VM's.

Filestore is a managed file storage service specifically designed for Google Cloud resources. It provides high availability, low latency storage and can handle replication, availability and other tasks.  It provides an NFS export that can be mounted on anything with an NFS client, and recently Google [started supporting NFS](https://cloud.google.com/run/docs/using-network-file-systems) through Cloud Run's [second generation execution environment](https://cloud.google.com/run/docs/configuring/execution-environments).

## Deployment Process
Deploying an app, such as WordPress, with Filestore support will require:

* Install WordPress (or use an existing WP image, which we're going to do)
* Install an NFS client in your container
* Create and configure a Filestore instance for storing the application data.
* Deploy the container on Cloud Run, mounting the Filestore instanceon startup

## Step 1: Create your container

In order for Cloud Run to be able to run WordPress, need to create a Dockerfile 
```
FROM library/wordpress:6-apache

USER root

RUN apt -q update && apt -qy install nfs-client nfs-server && apt clean
ADD ./init.sh .
ADD ./wp-config.php /var/www-local/core/wp-config.php

ENTRYPOINT ["./init.sh"]
```

The image will need to mount the NFS volume during startup, which is where `init.sh` comes into play.  You'll note a few overrides for NFS mount options, as well as server and share being passed in environment variables, which will be passed in to Cloud Run when the instance is created later.  We are also including a sample wp-config.php which pulls DB parameters and site URL from environment variables.
```
#!/usr/bin/env bash

echo test
if [ -z "${WP_NFS_SERVER}" -o -z "${WP_NFS_SHARE}" ]
then
  echo "Running WordPress without NFS mount.  To mount NFS, set WP_NFS_SERVER and WP_NFS_SHARE"
else
  rpc.statd & rpcbind -f & echo "docker NFS client with rpcbind ENABLED..."
  # Wait a moment for rpcbind to start up before trying to mount
  sleep 1
  NFS_FLAGS="-o nolock,nfsvers=${WP_NFS_VERSION-3}"
  echo mounting NFS with: mount ${NFS_FLAGS} "${WP_NFS_SERVER}:${WP_NFS_SHARE}" /var/www/
  if ! (mount ${NFS_FLAGS} "${WP_NFS_SERVER}:${WP_NFS_SHARE}" /var/www/); then
    echo "Failed to mount NFS, exiting"
    exit 1
  fi
fi

# This entrypoint script is provided by the WordPress image
docker-entrypoint.sh apache2-foreground &
# Wait a second for Apache to start, then start pulling logs out for GCP Logging
sleep 1
tail -f /var/log/apache2/*
```
You can either populate your NFS share with a fully-baked WordPress, or let the image populate your NFS with the default one.

Now, let's have Cloud Build push the image to Artifact Store using a trigger.  Here's a sample trigger file:
```
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build',
          '-t', 'us-west1-docker.pkg.dev/$PROJECT_ID/wordpress/wordpress-nfs:latest',
          'image/'
        ]
images:
- 'us-west1-docker.pkg.dev/$PROJECT_ID/wordpress/wordpress-nfs:latest'

options:
  logging: CLOUD_LOGGING_ONLY
```
You can use any build tool for this, but the image must be pushed to Artifact Registry (or GCR) for Cloud Run to be able to use it.

## Step 2: Create and Configure a Filestore Instance and Serverless VPC Access connector
Let's create a Filestore instance for our WordPress files.  Filestore requires a minimum 1TB filesystem, so it's worth considering sharing this instance with other workloads.  In order to mount a Filestore, we'll have to deploy a Serverless VPC Access Connector.  We'll do this with gcloud, but the sample repo has Terraform examples as well.
```
# Create a VPC, assuming you don't already have one to deploy into
gcloud compute networks create wptest1
# Create the Serverless VPC Access Connector
gcloud compute networks vpc-access connectors create wp-nfs1 --region us-west1 --range 10.1.0.0/28 --network wptest1
# Create the Filestore - this will ask you to enable the filestore api if it's not already enabled.
gcloud filestore instances create --file-share=capacity=1tb,name=wptest --network=name=wptest1 --zone=us-west1-a wp-nfs
```

## Step 3: Deploy a CloudSQL DB for WordPress to use
We will need a MySQL DB for WordPress
```
gcloud sql instances create wordpress --tier db-g1-small --database-version=MYSQL_8_0 --region=us-west1
gcloud sql databases create wordpress --instance wordpress
gcloud sql users create wordpress -i wordpress --password 'wptest%f1!'

# Store the secret in Secrets Manager
gcloud services enable secretmanager.googleapis.com
echo 'wptest%f1!'|gcloud secrets create wp-db-pass --data-file=-
```

## Step 4: Deploy the Application
The next step is to deploy the application on Cloud Run, making sure to reference the Filestore instance in environment variables.
```
# Get project id and number
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects list --filter="$PROJECT_ID" --format="value(PROJECT_NUMBER)")
# Grant the default service account access to the DB password
gcloud beta secrets add-iam-policy-binding wp-db-pass \
    --member serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
    --role=roles/secretmanager.secretAccessor

# Create the Cloud Run instance
FILESTORE_IP=$(gcloud filestore instances describe wp-nfs --zone us-west1-a --format="value(networks.ipAddresses[0])")
gcloud beta run deploy wordpress-nfs \
    --image=us-west1-docker.pkg.dev/${PROJECT_ID}/wordpress/wordpress-nfs:latest \
    --allow-unauthenticated \
    --port=80 \
    --service-account=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
    --set-env-vars="DB_HOST=localhost:/cloudsql/${PROJECT_ID}:us-west1:wordpress" \
    --set-env-vars='DB_USER=wordpress' \
    --set-env-vars='WP_NFS_SHARE=/wptest' \
    --set-env-vars='DB_NAME=wordpress' \
    --set-env-vars="WP_NFS_SERVER=${FILESTORE_IP}" \
    --set-env-vars='WP_BASEURL=https://wont-work-yet.run.google.com' \
    --set-cloudsql-instances=${PROJECT_ID}:us-west1:wordpress \
    --vpc-connector=projects/${PROJECT_ID}/locations/us-west1/connectors/wp-nfs1 \
    --set-secrets=DB_PASS=wp-db-pass:1 \
    --execution-environment=gen2 \
    --region=us-west1 \
    --project=${PROJECT_ID}
# Set the Base URL to the URL of the now-deployed app (can't get it until after it's deployed)
RUN_URL=$(gcloud run services describe wordpress-nfs --region=us-west1 --format="value(status.address.url)")
gcloud beta run deploy wordpress-nfs \
    --image=us-west1-docker.pkg.dev/${PROJECT_ID}/wordpress/wordpress-nfs:latest \
    --allow-unauthenticated \
    --port=80 \
    --service-account=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
    --set-env-vars="DB_HOST=localhost:/cloudsql/${PROJECT_ID}:us-west1:wordpress" \
    --set-env-vars='DB_USER=wordpress' \
    --set-env-vars='WP_NFS_SHARE=/wptest' \
    --set-env-vars='DB_NAME=wordpress' \
    --set-env-vars="WP_NFS_SERVER=${FILESTORE_IP}" \
    --set-env-vars="WP_BASEURL=${RUN_URL}" \
    --set-cloudsql-instances=${PROJECT_ID}:us-west1:wordpress \
    --vpc-connector=projects/${PROJECT_ID}/locations/us-west1/connectors/wp-nfs1 \
    --set-secrets=DB_PASS=wp-db-pass:1 \
    --execution-environment=gen2 \
    --region=us-west1 \
    --project=${PROJECT_ID}
```
You should now be able to reach your site at the Service URL listed in the output from the above deploy command.