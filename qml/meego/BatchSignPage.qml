import QtQuick 1.1
import com.nokia.meego 1.0
import "Component"
import "Delegate"
import "../js/main.js" as Script
import "../js/storage.js" as Database
import "../js/const.js" as Const

Page {
    id: page;

    tools: ToolBarLayout {
        ToolIcon {
            platformIconId: "toolbar-back";
            onClicked: pageStack.pop();
        }
        ToolIcon {
            id: playButton;
            platformIconId: "toolbar-mediacontrol-play";
            onClicked: internal.sign();
            states: [
                State {
                    name: "running";
                    PropertyChanges {
                        target: playButton;
                        platformIconId:"toolbar-mediacontrol-stop";
                        onClicked: internal.cancelSign();
                    }
                    when: internal.loading;
                }
            ]
        }
        ToolIcon {
            platformIconId: "toolbar-add";
            enabled: !internal.loading;
            onClicked: addTiebaDialog.open();
        }
        ToolIcon {
            platformIconId: "toolbar-delete";
            enabled: !internal.loading;
            onClicked: {
                dialog.createQueryDialog(qsTr("Warning"),
                                         qsTr("Do you want to clear your sign list?"),
                                         qsTr("OK"),
                                         qsTr("Cancel"),
                                         internal.clear)
            }
        }
    }

    Connections {
        target: signalCenter;
        onUserChanged: { internal.cancelSign(); internal.tbs = ""; }
    }

    QtObject {
        id: internal;

        property bool loading: false;
        property int currentIndex: -1;
        property string tbs: Script.tbs;

        function getThreadList(fname){
            signalCenter.showBusyIndicator();
            var param = {
                ctime: Date.now(),
                kw: encodeURIComponent(fname),
                pn: 1,
                rn: 35,
                st_type: "tb_forumlist"
            }
            Script.sendWebRequest(Const.F_FRS_PAGE, Script.tiebaParam(param), loadThreadList);
        }
        function loadThreadList(oritxt){
            var obj = JSON.parse(oritxt);
            if (obj.error_code != 0){
                signalCenter.showMessage(obj.error_msg);
            } else {
                internal.tbs = obj.anti.tbs;
                Script.tbs = obj.anti.tbs;
                if (obj.forum.sign_in_info.forum_info.is_on == 1){
                    insertForum(obj.forum.id, obj.forum.name);
                } else {
                    signalCenter.showMessage(qsTr("Signing is disabled"));
                }
            }
            signalCenter.hideBusyIndicator();
        }

        function requestTBS(){
            var param = { ctime: Date.now() }
            Script.sendWebRequest(Const.F_FORUM_FAVOCOMMEND, Script.tiebaParam(param), loadTBS);
        }
        function loadTBS(oritxt){
            var obj = JSON.parse(oritxt);
            if (obj.error_code != 0){
                signalCenter.showMessage(obj.error_msg);
                loading = false;
            } else {
                internal.tbs = obj.anti.tbs;
                Script.tbs = obj.anti.tbs;
                sign();
            }
        }

        function sign(){
            loading = true;
            currentIndex = -1;
            if (internal.tbs.length == 0){
                requestTBS();
            } else {
                resetSignState();
                signTimer.restart();
            }
        }

        function cancelSign(){
            loading = false;
            signTimer.stop();
            currentIndex = -1;
        }

        function startNextSign(){
            currentIndex ++;
            if (currentIndex < listModel.count){
                var data = listModel.get(currentIndex);
                singleSign(data.fid, data.fname);
            } else {
                signTimer.stop();
                loading = false;
                signalCenter.showMessage(qsTr("All Complete!"));
            }
        }

        function singleSign(fid, fname){
            setModelProperty(fid, 1, "");
            var param = {
                fid: fid,
                kw: encodeURIComponent(fname),
                tbs: Script.tbs
            }
            Script.sendWebRequest(Const.C_FORUM_SIGN, Script.tiebaParam(param), singleSignResult, fid);
        }
        function singleSignResult(oritxt, fid){
            var obj = JSON.parse(oritxt);
            if (obj.error_code != 0){
                setModelProperty(fid, 3, obj.error_msg);
            } else {
                setModelProperty(fid, 2, qsTr("Rank: %1").arg(obj.user_info.user_sign_rank));
            }
        }
        function loadFromFavourite(){
            try {
                var obj = JSON.parse(utility.getCache("myBarList"));
                if (obj.error_code == 0){
                    Database.deleteSignTieba();
                    var list = [];
                    obj.forum_list.forEach(function(value){
                                               var obj = {"fid": value.id, "fname": value.name};
                                               list.push(obj);
                                           })
                    Database.addSignTieba(list);
                    Database.getSignTieba(listModel);
                }
            } catch(e){
                signalCenter.showMessage(qsTr("Cannot import your favourite tieba. Please refresh your homepage"));
            }
        }
        function insertForum(fid, fname){
            var obj = {"fid": fid, "fname": fname, "state": 0, "errmsg": ""}
            if (getModelIndexByFid(fid) == -1){ listModel.append(obj) }
            Database.addSignTieba([obj]);
        }
        function getModelIndexByFid(fid){
            for (var i=0, l=listModel.count;i<l;i++){
                if (listModel.get(i).fid == fid){
                    return i;
                }
            }
            return -1;
        }
        function setModelProperty(fid, state, errmsg){
            for (var i=0, l=listModel.count;i<l;i++){
                if (listModel.get(i).fid == fid){
                    listModel.set(i, {"state": state, "errmsg": errmsg});
                    break;
                }
            }
        }
        function resetSignState(){
            for (var i=0, l=listModel.count; i<l; i++){
                listModel.setProperty(i, "state", 0);
            }
        }
        function clear(){
            Database.deleteSignTieba();
            listModel.clear();
            signalCenter.showMessage(qsTr("Completed"));
        }
    }

    Sheet {
        id: addTiebaDialog;
        acceptButtonText: qsTr("OK");
        rejectButtonText: qsTr("Cancel");

        content: Flickable {
            id: flickable;
            anchors.fill: parent;
            clip: true;
            contentWidth: parent.width;
            contentHeight: addTiebaDialogCol.height;
            Column {
                id: addTiebaDialogCol;
                anchors.horizontalCenter: parent.horizontalCenter;
                spacing: constant.paddingMedium;
                Item { width: 1; height: 1; }
                Text { text: qsTr("Add Tieba To Sign"); font.pixelSize: constant.fontSizeMedium; color: constant.colorMid; }
                TextField {
                    id: addTiebaDialogTextField;
                    width: addTiebaDialogButton.width;
                    placeholderText: qsTr("Tap To Input");
                }
                Button {
                    id: addTiebaDialogButton;
                    text: qsTr("Import from my favourite");
                    onClicked: {
                        dialog.createQueryDialog(qsTr("Warning"),
                                                 qsTr("This operation will clear your sign list, continue?"),
                                                 qsTr("OK"),
                                                 qsTr("Cancel"),
                                                 internal.loadFromFavourite)
                        addTiebaDialog.close();
                    }
                }
            }
        }

        onStatusChanged: {
            if (status == DialogStatus.Opening){
                addTiebaDialogTextField.text = "";
            }
        }

        onAccepted: {
            if (addTiebaDialogTextField.text.length > 0){
                internal.getThreadList(addTiebaDialogTextField.text);
            }
        }
    }

    Timer {
        id: signTimer;
        interval: 6000;
        repeat: true;
        triggeredOnStart: true;
        onTriggered: internal.startNextSign();
    }

    ViewHeader {
        id: viewHeader;
        headerText: loading ? qsTr("Now Signing[%1/%2]").arg(internal.currentIndex+1).arg(listModel.count) : qsTr("Sign Manager");
        loading: internal.loading;
    }

    ListView {
        id: view;
        anchors { fill: parent; topMargin: viewHeader.height; }
        model: ListModel { id: listModel; }
        delegate: deleComp;
        Component {
            id: deleComp;
            AbstractDelegate {
                id: root;
                enabled: !internal.loading;
                onClicked: internal.singleSign(model.fid, model.fname);
                onPressAndHold: {
                    deleteConfirm.index = index;
                    deleteConfirm.fid = model.fid;
                    deleteConfirm.open();
                }
                Column {
                    anchors { left: root.paddingItem.left; right: root.paddingItem.right; verticalCenter: parent.verticalCenter; }
                    Text {
                        text: model.fname;
                        font.pixelSize: constant.fontSizeLarge;
                        color: constant.colorLight;
                    }
                    Text {
                        text: getText();
                        font { pixelSize: constant.fontSizeSmall; weight: Font.Light; }
                        color: constant.colorMid;
                        function getText(){
                            switch (model.state){
                            case 0: return qsTr("Waiting for sign");
                            case 1: return qsTr("Signing");
                            case 2: return qsTr("Success!")+model.errmsg;
                            case 3: return model.errmsg;
                            }
                        }
                    }
                }
            }
        }
    }

    ScrollDecorator { flickableItem: view; }

    SelectionDialog {
        id: deleteConfirm;
        property int index: -1;
        property string fid: "";
        titleText: qsTr("Warning");
        model: [qsTr("Delete this forum")];
        onAccepted: {
            Database.deleteSignTieba(deleteConfirm.fid);
            listModel.remove(deleteConfirm.index);
        }
    }

    Component.onCompleted: {
        Database.getSignTieba(listModel);
    }
}
