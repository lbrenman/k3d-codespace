# Lab 06: Deploying WordPress + MySQL
# ─────────────────────────────────────────────────────────────────────────────
# A classic two-tier application: WordPress (PHP frontend) backed by MySQL.
# This lab focuses on deploying real production software and introduces
# PersistentVolumeClaims in a practical context — without persistent storage,
# your WordPress posts and MySQL data would vanish every time a pod restarts.
#
# HOW TO USE THIS LAB:
#   Copy and paste each command block into your terminal one step at a time.
#   Do not run this file as a script.
#
# What you will build:
#
#   Browser
#     │
#     │ :8080 (Codespace → k3d LoadBalancer → Traefik Ingress)
#     ▼
#   ┌──────────────────────────────────────────────────────────────────┐
#   │  Namespace: wordpress                                            │
#   │                                                                  │
#   │  ┌─────────────────────────────────────────────────────────┐    │
#   │  │  Deployment: wordpress                                  │    │
#   │  │  image: wordpress:6-apache                              │    │
#   │  │  env: WORDPRESS_DB_HOST, _USER, _PASSWORD, _NAME        │    │
#   │  │       (from Secret)                                     │    │
#   │  │                          │                              │    │
#   │  │  PVC: wordpress-pvc ─────┘ /var/www/html (themes,      │    │
#   │  │       (1Gi)                 plugins, uploads)           │    │
#   │  └──────────────────┬──────────────────────────────────────┘    │
#   │                     │ Service: wordpress-svc :80                │
#   │                     │                                           │
#   │  ┌──────────────────▼──────────────────────────────────────┐    │
#   │  │  Deployment: mysql                                      │    │
#   │  │  image: mysql:8.0                                       │    │
#   │  │  env: MYSQL_ROOT_PASSWORD, MYSQL_DATABASE,              │    │
#   │  │       MYSQL_USER, MYSQL_PASSWORD (from Secret)          │    │
#   │  │                          │                              │    │
#   │  │  PVC: mysql-pvc ─────────┘ /var/lib/mysql (data files) │    │
#   │  │       (2Gi)                                             │    │
#   │  └─────────────────────────────────────────────────────────┘    │
#   │                     │ Service: mysql-svc :3306 (ClusterIP)      │
#   └──────────────────────────────────────────────────────────────────┘
#
# Key concepts: PersistentVolumeClaim, Secret, multi-container app,
#               service discovery by DNS name, StatefulSets vs Deployments

# ── Step 1: Create namespace ──────────────────────────────────────────────────
kubectl create namespace lab06

# ── Step 2: Create a Secret for database credentials ─────────────────────────
# Never hardcode passwords in Deployment manifests.
# Both WordPress and MySQL will read credentials from this Secret.
kubectl create secret generic mysql-credentials \
  --from-literal=MYSQL_ROOT_PASSWORD=rootpassword \
  --from-literal=MYSQL_DATABASE=wordpress \
  --from-literal=MYSQL_USER=wp_user \
  --from-literal=MYSQL_PASSWORD=wp_password \
  -n lab06

kubectl get secret mysql-credentials -n lab06

# ── Step 3: Create PersistentVolumeClaims ────────────────────────────────────
# PVCs reserve durable storage that survives pod restarts and rescheduling.
# Without these, all WordPress content and MySQL data would be lost on restart.
kubectl apply -n lab06 -f - <<YAML
# MySQL data — needs more space for DB files
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
# WordPress files — themes, plugins, uploads
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
YAML

kubectl get pvc -n lab06
# STATUS will show Pending — this is expected and normal in k3d.
# k3d uses the local-path StorageClass which uses late binding, meaning
# the volume is not actually provisioned until a pod mounts it.
# The PVCs will flip to Bound automatically once MySQL and WordPress pods start.
# Do not wait here — proceed to the next step and deploy MySQL.

# ── Step 4: Deploy MySQL ──────────────────────────────────────────────────────
kubectl apply -n lab06 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_DATABASE
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_PASSWORD
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
        readinessProbe:
          exec:
            command: [mysqladmin, ping, -h, localhost]
          initialDelaySeconds: 20
          periodSeconds: 10
          failureThreshold: 6
      volumes:
      - name: mysql-data
        persistentVolumeClaim:
          claimName: mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-svc
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
  clusterIP: None    # Headless service — direct pod DNS, no load balancing needed
YAML

# Wait for MySQL to be ready before deploying WordPress
kubectl get pods -n lab06 -w
# Press Ctrl+C once mysql pod shows READY 1/1

# ── Step 5: Deploy WordPress ──────────────────────────────────────────────────
kubectl apply -n lab06 -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:6-apache
        ports:
        - containerPort: 80
        env:
        # WordPress connects to MySQL using the Service DNS name: mysql-svc
        - name: WORDPRESS_DB_HOST
          value: mysql-svc
        - name: WORDPRESS_DB_NAME
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_DATABASE
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_USER
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: MYSQL_PASSWORD
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: wordpress-data
          mountPath: /var/www/html
        readinessProbe:
          httpGet:
            path: /wp-login.php
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 6
      volumes:
      - name: wordpress-data
        persistentVolumeClaim:
          claimName: wordpress-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress-svc
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
YAML

# ── Step 6: Wait for WordPress to be ready ────────────────────────────────────
kubectl get pods -n lab06 -w
# WordPress takes ~30-60s to start as it initialises the DB on first run
# Press Ctrl+C once wordpress pod shows READY 1/1

# ── Step 7: Create an Ingress for WordPress ──────────────────────────────────
# Instead of port-forward, we expose WordPress through the k3d Traefik Ingress
# on port 8080. This avoids the Host header issues that cause WordPress to
# redirect to localhost when using port-forward in a Codespace environment.
#
# We use a pathPrefix of /wordpress so it doesn't conflict with other labs
# that may be using port 8080.
kubectl apply -n lab06 -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wordpress-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: wordpress-svc
            port:
              number: 80
YAML

# Tell WordPress to use the port 8080 Codespace URL — get it from the PORTS
# tab in VS Code (the URL next to port 8080).
# Replace the URL below with your actual port 8080 Codespace URL:
kubectl set env deployment/wordpress   WORDPRESS_CONFIG_EXTRA="define('WP_HOME','https://<your-codespace-name>-8080.app.github.dev'); define('WP_SITEURL','https://<your-codespace-name>-8080.app.github.dev');"   -n lab06

kubectl rollout status deployment/wordpress -n lab06

# Visit the port 8080 Codespace URL in your browser — open the PORTS tab,
# find port 8080 and click the globe icon.
# You should see the WordPress installation/setup page.
# Complete the setup: choose a site title, admin username and password.
# WordPress will use the Codespace URL consistently for all redirects.

# ── Step 8: Verify persistence ────────────────────────────────────────────────
# Delete the WordPress pod — Kubernetes will recreate it using the same PVC.
# Unlike port-forward, the Ingress keeps working through pod restarts
# because it routes to the Service, not directly to a pod.
kubectl delete pod -n lab06 -l app=wordpress

kubectl get pods -n lab06 -w
# Press Ctrl+C once the new pod shows READY 1/1

# Visit the same port 8080 Codespace URL in your browser —
# your WordPress setup (site title, admin account) should still be there,
# confirming the data survived the pod restart via the PVC.
# No need to restart port-forward — the Ingress handles it automatically.

# ── Step 9: Inspect the PVCs and storage ─────────────────────────────────────
kubectl get pvc -n lab06
# Both PVCs show Bound and the storage sizes you requested

kubectl describe pvc mysql-pvc -n lab06
# Shows the StorageClass used and the volume it bound to

# ── Step 10: Connect to MySQL directly ───────────────────────────────────────
MYSQL_POD=$(kubectl get pod -n lab06 -l app=mysql -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $MYSQL_POD -n lab06 -- \
  mysql -u wp_user -pwp_password wordpress -e "SHOW TABLES;"
# Lists the WordPress tables created during setup

# ── Step 11: Clean up ────────────────────────────────────────────────────────
kubectl delete namespace lab06
# Note: deleting the namespace also deletes the PVCs and their data


# ── Further Reading ───────────────────────────────────────────────────────────
# Persistent Volumes:
#   https://kubernetes.io/docs/concepts/storage/persistent-volumes/
# PersistentVolumeClaims:
#   https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims
# StorageClasses:
#   https://kubernetes.io/docs/concepts/storage/storage-classes/
# Example: Deploying WordPress and MySQL with Persistent Volumes (official):
#   https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/