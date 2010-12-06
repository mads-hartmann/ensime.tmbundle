/**
* Navigator.js 
*
* This js allows the user to navigate the packages and memebers of each package 
* using the arrow-keys. 
* By typing something into the search field it will filter the list of members. 
* Hitting enter will open the file where the selected member is defined
*/
$(document).ready(function() {

	var input = $(".top input[type=search]"),
	    index_count = -1;
	input.focus();

	/**
	 * Takes care of filtering the list of visible members when 
	 * the user types something into the search field.
	 */
	input.bind('input', function() {
		var value = input.val();

		var all = $('li.selectable'),
			show = all.filter(function(index) {
			var txt = $(this).find("p a").text(); // a tags are neseted inside p tags. 
			return (txt.toLowerCase().match(new RegExp("^\s*" + value.toLowerCase())) !== null);
		}),
			hide = all.not(show);

		show.show();
		$('.selected').removeClass('selected');
		show.eq(0).addClass('selected');
		hide.hide();
		index_count = 0;
	});

  /**
  * Opens hte file represented at the current node. 
  */
	function openFile(node) {
		var cmd = 'open "' + node.find('a').attr('href') + '"';
		myCommand = TextMate.system(cmd);
		window.close();
		myCommand.onreadoutput = function(str) {
			console.log("read: " + str);
		};
		myCommand.onreaderror = function(str) {
			console.log("error: " + str);
		};
	}

	$(document).bind('keydown', function(e) {
		var key = e.which || e.charCode || e.keyCode || 0,
		  all = $('li.selectable').filter(':visible'),
			that = ($('.selected').size() > 0) ? $('.selected').eq(0) : $('li').filter('.selectable').filter(':visible').eq(0),
		  count = all.size(),
  	  DOWN = 40,
    	UP = 38,
    	TAB = 9,
    	ENTER = 13,
    	ESC = 27;

		switch (key) {
		case DOWN:
			{
				down();
				break;
			}
		case UP:
			{
				up();
				break;
			}
		case ENTER:
			{
				openFile(that);
			}
		case ESC:
			{
				if (inputIsEmpty()) {
					window.close();
					return false;
				}
				input.val("");
				input.trigger('input');
				return false;
			}
		default:
			{
				return true;
			}
		}

		function up() {
			index_count--;
			if (index_count < 0) {
			  index_count = 0;
		  } else {
		    var next = all.eq(index_count);
		    that.removeClass('selected');
		    next.addClass('selected');
		  }			
		}

		function down() {
			index_count++;
			if (index_count >= count) {
				index_count = count-1;
			} else {
			  var next = all.eq(index_count);
		    that.removeClass('selected');
		    next.addClass('selected');
			}
		}

		function inputIsEmpty() {
			return (input.val() == "");
		}

		// Now move the list up/down
		// -------------------------
		var content = $('#content'),
			scrollbarOffset = content.scrollTop(),
			rowHeight = $('ul li').eq(0).height() + 20,
			//padding (20)
		  maxOffset = content.height() + content.offset().top - 16,
			// 16 for the scrollbar
		  itemOffset = offsetTop = $('.selected').eq(0).offset().top;

		if (itemOffset >= maxOffset) {
			content.scrollTop(scrollbarOffset + rowHeight + 20); // 20 is just extra spacing.
		} else if (itemOffset <= 0) {
			content.scrollTop(scrollbarOffset - rowHeight - 20);
		}

		return false;

	});
});