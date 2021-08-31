TEMPDIR=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 10 | head -n 1)
NAMESPACE=<env> <1>
mkdir $TEMPDIR
openssl genrsa -out $TEMPDIR/key.pem 1024
openssl rsa -in $TEMPDIR/key.pem -pubout -outform DER -out $TEMPDIR/pubkey.der
openssl pkcs8 -topk8 -in $TEMPDIR/key.pem -nocrypt -outform DER -out $TEMPDIR/key.der
echo key.public=$(xxd -p $TEMPDIR/key.der | tr -d '\n') > $TEMPDIR/secret.yml
echo key.private=$(xxd -p $TEMPDIR/pubkey.der | tr -d '\n') >> $TEMPDIR/secret.yml
kubectl create secret generic activation-key --from-file=activation-secret=$TEMPDIR/secret.yml -n $NAMESPACE
rm $TEMPDIR/key.pem
rm $TEMPDIR/pubkey.der
rm $TEMPDIR/key.der
rm $TEMPDIR/secret.yml
rmdir $TEMPDIR