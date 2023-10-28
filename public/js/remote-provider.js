function inherits(B, A) {
    function I() {}
    I.prototype = A.prototype;
    B.prototype = new I();
    B.prototype.constructor = B;
}

function getCustomRemoteProvider() {

    var CustomProvider = function(options) {
        H.map.provider.RemoteTileProvider.call(this);
    };

    inherits(CustomProvider, H.map.provider.RemoteTileProvider);

    CustomProvider.prototype.requestInternal = {};
    //console.log("inherits:", CustomProvider.prototype.requestInternal);
    return { it: CustomProvider };
}